public with sharing class OncoGlobal_ParseReceiptImage {

    @TestVisible private static final String MINDEE_MODEL_ID = '7a037276-361c-40f4-be15-8f397e9adc15';
    @TestVisible private static final String MINDEE_ENQUEUE_PATH = '/v2/products/extraction/enqueue';
    @TestVisible private static final String MINDEE_GET_PATH = '/v2/products/extraction/results/';
    @TestVisible private static final Integer MAX_POLLS = 30;

    public class Request {
        @InvocableVariable(required=true label='Content Document Id' description='ContentDocumentId of the receipt image in Salesforce Files.')
        public String contentDocumentId;
        @InvocableVariable(label='Visit Log Id' description='Optional Visit_Log__c Id to link the resulting Expense to.')
        public String visitLogId;
        @InvocableVariable(label='Sales Rep Id' description='Optional User Id; defaults to running user.')
        public String salesRepId;
        @InvocableVariable(label='Visit Context' description='Optional context string saved with the Expense.')
        public String visitContext;
    }

    public class Response {
        @InvocableVariable public String expenseId;
        @InvocableVariable public String parsedJson;
        @InvocableVariable public String confirmationMessage;
    }

    @InvocableMethod(
        label='OncoGlobal Parse Receipt Image'
        description='Sends a receipt image to Mindee v2 (enqueue + poll) via NC_Mindee, then creates an Expense__c record from the structured response.'
    )
    public static List<Response> parseReceipt(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(processOne(req));
        }
        return results;
    }

    private static Response processOne(Request req) {
        Response resp = new Response();
        if (String.isBlank(req.contentDocumentId)) {
            resp.confirmationMessage = 'No receipt image provided. ❌';
            return resp;
        }

        List<ContentVersion> versions = [
            SELECT Id, VersionData, Title, FileType, FileExtension, PathOnClient
            FROM ContentVersion
            WHERE ContentDocumentId = :req.contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            resp.confirmationMessage = 'Receipt file not found in Salesforce Files. ❌';
            return resp;
        }
        ContentVersion cv = versions[0];

        String mimeType = mapMimeType(cv.FileType);
        String filename = String.isNotBlank(cv.PathOnClient)
            ? cv.PathOnClient
            : cv.Title + '.' + (cv.FileExtension == null ? 'png' : cv.FileExtension.toLowerCase());

        String finalBody;
        try {
            finalBody = callMindeeV2(cv.VersionData, filename, mimeType);
        } catch (Exception e) {
            resp.confirmationMessage = 'Mindee callout failed: ' + e.getMessage() + ' ❌';
            resp.parsedJson = e.getMessage();
            return resp;
        }
        resp.parsedJson = finalBody;

        Map<String, Object> prediction;
        try {
            prediction = extractPrediction(finalBody);
        } catch (Exception e) {
            resp.confirmationMessage = 'Could not parse Mindee response. ⚠️';
            return resp;
        }
        if (prediction == null) {
            resp.confirmationMessage = 'Receipt could not be read or response shape unrecognised. See parsedJson. ⚠️';
            return resp;
        }

        try {
            Expense__c exp = buildExpense(prediction, req);
            insert exp;
            resp.expenseId = exp.Id;
            String amountStr = exp.Amount__c == null ? '?' : String.valueOf(exp.Amount__c.setScale(2));
            String catStr = exp.Category__c == null ? '' : exp.Category__c;
            resp.confirmationMessage = '₹' + amountStr + ' ' + catStr + ' logged from receipt ✅';
        } catch (Exception e) {
            resp.confirmationMessage = 'Failed to save expense: ' + e.getMessage() + ' ❌';
        }
        return resp;
    }

    private static String callMindeeV2(Blob fileData, String filename, String mimeType) {
        HttpResponse enqueueResp = enqueueInference(fileData, filename, mimeType);
        if (enqueueResp.getStatusCode() < 200 || enqueueResp.getStatusCode() >= 300) {
            throw new CalloutException('enqueue HTTP ' + enqueueResp.getStatusCode() + ': ' + enqueueResp.getBody());
        }

        Map<String, Object> enqBody = (Map<String, Object>) JSON.deserializeUntyped(enqueueResp.getBody());
        String jobId = findId(enqBody);
        if (String.isBlank(jobId)) {
            throw new CalloutException('No job id in enqueue response: ' + enqueueResp.getBody());
        }

        String lastBody = '';
        for (Integer i = 0; i < MAX_POLLS; i++) {
            HttpResponse pollResp = getInference(jobId);
            Integer sc = pollResp.getStatusCode();
            String body = pollResp.getBody();
            lastBody = body;

            if (sc == 404 && body != null && (body.contains('404-008') || body.toLowerCase().contains('not ready'))) {
                continue;
            }
            if (sc < 200 || sc >= 300) {
                throw new CalloutException('poll HTTP ' + sc + ': ' + body);
            }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
            String status = findStatus(root);
            if (status != null) {
                String s = status.toLowerCase();
                if (s == 'processed' || s == 'completed' || s == 'success' || s == 'succeeded' || s == 'done') {
                    return body;
                }
                if (s == 'failed' || s == 'error') {
                    throw new CalloutException('Mindee inference failed: ' + body);
                }
            }
            if (extractPrediction(body) != null) return body;
        }
        throw new CalloutException('Mindee inference still processing after ' + MAX_POLLS + ' polls. Last response: ' + lastBody);
    }

    private static HttpResponse enqueueInference(Blob fileData, String filename, String mimeType) {
        String boundary = '----SfdcMindeeBoundary' + DateTime.now().getTime();
        String b64File = EncodingUtil.base64Encode(fileData);

        String body = '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="model_id"\r\n\r\n'
            + MINDEE_MODEL_ID + '\r\n'
            + '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="file_base64"\r\n\r\n'
            + b64File + '\r\n'
            + '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="filename"\r\n\r\n'
            + filename + '\r\n'
            + '--' + boundary + '--\r\n';

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:NC_Mindee' + MINDEE_ENQUEUE_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setHeader('Accept', 'application/json');
        req.setBody(body);
        req.setTimeout(60000);
        return new Http().send(req);
    }

    private static HttpResponse getInference(String jobId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:NC_Mindee' + MINDEE_GET_PATH + jobId);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        return new Http().send(req);
    }

    private static Blob buildMultipartBodyV2(String boundary, Blob fileData, String filename, String mimeType) {
        String preFields = '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="model_id"\r\n\r\n'
            + MINDEE_MODEL_ID + '\r\n'
            + '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="file"; filename="' + filename + '"\r\n'
            + 'Content-Type: ' + mimeType + '\r\n\r\n';
        while (Math.mod(preFields.length(), 3) != 0) preFields += ' ';

        String postFile = '\r\n--' + boundary + '--';

        return EncodingUtil.base64Decode(
            EncodingUtil.base64Encode(Blob.valueOf(preFields)) +
            EncodingUtil.base64Encode(fileData) +
            EncodingUtil.base64Encode(Blob.valueOf(postFile))
        );
    }

    private static String findId(Map<String, Object> body) {
        if (body == null) return null;
        for (String key : new List<String>{ 'job', 'inference', 'data' }) {
            Object child = body.get(key);
            if (child instanceof Map<String, Object>) {
                Object id = ((Map<String, Object>) child).get('id');
                if (id != null) return String.valueOf(id);
            }
        }
        Object id = body.get('id');
        return id == null ? null : String.valueOf(id);
    }

    private static String findStatus(Map<String, Object> body) {
        if (body == null) return null;
        for (String key : new List<String>{ 'job', 'inference', 'data' }) {
            Object child = body.get(key);
            if (child instanceof Map<String, Object>) {
                Object s = ((Map<String, Object>) child).get('status');
                if (s != null) return String.valueOf(s);
            }
        }
        Object st = body.get('status');
        return st == null ? null : String.valueOf(st);
    }

    private static Map<String, Object> extractPrediction(String body) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        return extractPrediction(root);
    }

    private static Map<String, Object> extractPrediction(Map<String, Object> root) {
        if (root == null) return null;
        for (String top : new List<String>{ 'inference', 'data' }) {
            Object level = root.get(top);
            if (level instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) level;
                for (String innerKey : new List<String>{ 'result', 'prediction', 'fields' }) {
                    Object lv = m.get(innerKey);
                    if (lv instanceof Map<String, Object>) {
                        Map<String, Object> mm = (Map<String, Object>) lv;
                        Object f = mm.get('fields');
                        if (f instanceof Map<String, Object>) return (Map<String, Object>) f;
                        return mm;
                    }
                }
            }
        }
        for (String innerKey : new List<String>{ 'result', 'prediction', 'fields' }) {
            Object lv = root.get(innerKey);
            if (lv instanceof Map<String, Object>) {
                Map<String, Object> mm = (Map<String, Object>) lv;
                Object f = mm.get('fields');
                if (f instanceof Map<String, Object>) return (Map<String, Object>) f;
                return mm;
            }
        }
        return null;
    }

    private static String mapMimeType(String fileType) {
        if (fileType == null) return 'application/octet-stream';
        String t = fileType.toUpperCase();
        if (t == 'PNG') return 'image/png';
        if (t == 'JPG' || t == 'JPEG') return 'image/jpeg';
        if (t == 'PDF') return 'application/pdf';
        if (t == 'HEIC') return 'image/heic';
        if (t == 'WEBP') return 'image/webp';
        if (t == 'TIF' || t == 'TIFF') return 'image/tiff';
        return 'application/octet-stream';
    }

    private static Expense__c buildExpense(Map<String, Object> p, Request req) {
        Expense__c exp = new Expense__c();
        Decimal amt = decimalFromAny(p, new List<String>{ 'total_amount', 'totalAmount', 'amount', 'total' });
        exp.Amount__c = amt == null ? 0 : amt;

        exp.Merchant__c = abbreviate(stringFromAny(p, new List<String>{ 'supplier_name', 'merchant_name', 'merchant', 'supplier' }), 255);

        String dateStr = stringFromAny(p, new List<String>{ 'date', 'purchase_date', 'transaction_date' });
        if (String.isNotBlank(dateStr)) {
            try { exp.Expense_Date__c = Date.valueOf(dateStr); }
            catch (Exception e) { exp.Expense_Date__c = Date.today(); }
        } else {
            exp.Expense_Date__c = Date.today();
        }

        String mindeeCat = stringFromAny(p, new List<String>{ 'category', 'expense_category' });
        exp.Category__c = mapCategory(mindeeCat, exp.Merchant__c);

        Decimal conf = confidenceFromAny(p, new List<String>{ 'total_amount', 'totalAmount', 'amount', 'total' });
        exp.OCR_Confidence__c = mapConfidence(conf);

        exp.Notes__c = abbreviate(buildNotes(p, req.visitContext), 2048);

        exp.Receipt_Image_URL__c = '/lightning/r/ContentDocument/' + req.contentDocumentId + '/view';
        exp.Status__c = 'Submitted';
        if (String.isNotBlank(req.visitLogId)) exp.Visit_Log__c = req.visitLogId;
        exp.Sales_Rep__c = String.isBlank(req.salesRepId) ? UserInfo.getUserId() : req.salesRepId;
        return exp;
    }

    private static String buildNotes(Map<String, Object> p, String visitContext) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(visitContext)) parts.add(visitContext);
        for (String key : new List<String>{ 'line_items', 'lineItems' }) {
            Object liObj = p.get(key);
            if (liObj instanceof List<Object>) {
                for (Object o : (List<Object>) liObj) {
                    if (!(o instanceof Map<String, Object>)) continue;
                    Map<String, Object> li = (Map<String, Object>) o;
                    String descText = (String) li.get('description');
                    if (String.isBlank(descText)) descText = (String) li.get('name');
                    if (String.isNotBlank(descText)) parts.add(descText);
                }
                break;
            }
        }
        return String.join(parts, '; ');
    }

    private static Decimal decimalFromAny(Map<String, Object> p, List<String> keys) {
        for (String k : keys) {
            Object obj = p.get(k);
            if (obj == null) continue;
            if (obj instanceof Map<String, Object>) {
                Object v = ((Map<String, Object>) obj).get('value');
                Decimal d = toDecimal(v);
                if (d != null) return d;
            } else {
                Decimal d = toDecimal(obj);
                if (d != null) return d;
            }
        }
        return null;
    }

    private static String stringFromAny(Map<String, Object> p, List<String> keys) {
        for (String k : keys) {
            Object obj = p.get(k);
            if (obj == null) continue;
            if (obj instanceof Map<String, Object>) {
                Object v = ((Map<String, Object>) obj).get('value');
                if (v != null) return String.valueOf(v);
            } else {
                return String.valueOf(obj);
            }
        }
        return null;
    }

    private static Decimal confidenceFromAny(Map<String, Object> p, List<String> keys) {
        for (String k : keys) {
            Object obj = p.get(k);
            if (obj instanceof Map<String, Object>) {
                Object c = ((Map<String, Object>) obj).get('confidence');
                Decimal d = toDecimal(c);
                if (d != null) return d;
            }
        }
        return null;
    }

    private static Decimal toDecimal(Object v) {
        if (v == null) return null;
        if (v instanceof Decimal) return (Decimal) v;
        if (v instanceof Integer) return Decimal.valueOf((Integer) v);
        if (v instanceof Double) return Decimal.valueOf(String.valueOf((Double) v));
        if (v instanceof String) {
            try { return Decimal.valueOf((String) v); } catch (Exception e) { return null; }
        }
        return null;
    }

    private static String mapCategory(String mindeeCat, String merchant) {
        if (String.isNotBlank(mindeeCat)) {
            String c = mindeeCat.toLowerCase();
            if (c == 'food' || c == 'leisure' || c == 'meal' || c == 'meals' || c == 'restaurant') return 'Meals';
            if (c == 'transport' || c == 'gasoline' || c == 'parking' || c == 'toll' || c == 'taxi' || c == 'travel') return 'Travel';
            if (c == 'lodging' || c == 'hotel' || c == 'accommodation') return 'Accommodation';
        }
        return inferFromMerchant(merchant);
    }

    private static String inferFromMerchant(String merchant) {
        if (String.isBlank(merchant)) return 'Other';
        String m = merchant.toLowerCase();
        if (m.contains('ola') || m.contains('uber') || m.contains('taxi') || m.contains('cab')) return 'Travel';
        if (m.contains('cafe') || m.contains('restaurant') || m.contains('eats') || m.contains('food')) return 'Meals';
        if (m.contains('hotel') || m.contains('lodge') || m.contains('inn') || m.contains('resort')) return 'Accommodation';
        return 'Other';
    }

    private static String mapConfidence(Decimal conf) {
        if (conf == null) return 'Low';
        if (conf >= 0.9) return 'High';
        if (conf >= 0.7) return 'Medium';
        return 'Low';
    }

    private static String abbreviate(String s, Integer max) {
        if (s == null) return null;
        return s.length() > max ? s.substring(0, max) : s;
    }
}
