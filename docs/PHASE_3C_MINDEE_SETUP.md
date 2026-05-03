# Phase 3c Setup — Mindee Receipt Parser via Named Credential

`OncoGlobal_ParseReceiptImage.cls` calls Mindee through a Named Credential (`NC_Mindee`). This guide walks through creating the credential. **You do this once in Setup; the API key never leaves your browser.**

## 1. Sign up at Mindee (free)

1. Go to <https://platform.mindee.com/signup>
2. Create a free account — no credit card required
3. Free tier: **250 receipt parses/month**, no expiry

## 2. Generate an API key

1. After signup, go to: **API Keys** (top-right profile menu, or <https://platform.mindee.com/api-keys>)
2. Click **"Create new API key"** → name it `OncoGlobal`
3. Copy the key. It looks like a 32-char hex string. **Keep this tab open** — you'll paste it once into Salesforce in step 5.

## 3. Create the External Credential

1. In Salesforce: **Setup** → Quick Find: `External Credentials` → click **External Credentials**
2. Click **New**:
   - **Label**: `NC Mindee External`
   - **Name**: `NC_Mindee_External`
   - **Authentication Protocol**: `Custom`
3. Click **Save**

## 4. Add a Principal

1. On the External Credential detail page, scroll to **Principals** → click **New**:
   - **Parameter Name**: `NC_Mindee_Principal`
   - **Identity Type**: `Named Principal`
   - **Sequence Number**: `1`
2. Click **Save**

## 5. Add the API key as an Authentication Parameter

1. On the Principal you just created, in the **Authentication Parameters** section, click **New**:
   - **Name**: `apiKey`
   - **Value**: *paste the Mindee API key from step 2*
2. Click **Save**

> The value is encrypted at rest and never shown again in plain text.

## 6. Create the Named Credential

1. **Setup** → Quick Find: `Named Credentials` → **Named Credentials** tab → click **New**
2. Fill in:
   - **Label**: `NC Mindee`
   - **Name**: `NC_Mindee`
   - **URL**: `https://api-v2.mindee.net`
   - **Enabled**: ✓
   - **External Credential**: search and pick `NC Mindee External`
   - **Generate Authorization Header**: ☐ (unchecked — we set our own)
   - **Allow Formulas in HTTP Header**: ✓ (checked)
   - **Allow Formulas in HTTP Body**: optional (leave default)
3. Click **Save**

## 7. Add the Authorization custom header

Mindee v2 expects the API key directly in the `Authorization` header (no `Token` or `Bearer` prefix — confirmed in the OpenAPI spec at <https://api-v2.mindee.net/openapi.json>). We provide it via a Custom Header on the Named Credential.

1. Still on the Named Credential detail, scroll to **Custom Headers** → click **New**:
   - **Name**: `Authorization`
   - **Value**: `{!$Credential.NC_Mindee_External.apiKey}`
2. Click **Save**

> The merge field `{!$Credential.NC_Mindee_External.apiKey}` injects the encrypted API key at callout time.

## 8. Grant the running user access to the credential

1. **Setup** → Quick Find: `Permission Sets` → **New**:
   - **Label**: `OncoGlobal Mindee Access`
   - **API Name**: `OncoGlobal_Mindee_Access`
2. Save
3. From the permission set page, click **External Credential Principal Access** → **Edit**
4. Move `NC_Mindee_External - NC_Mindee_Principal` to **Enabled External Credential Principals**
5. Save
6. Click **Manage Assignments** → **Add Assignments** → pick yourself → **Assign**

## 9. Smoke test

1. Upload one of the sample receipts to Salesforce Files:
   - `samples/receipt_ola_cab.png` (expected: ₹379.06 Travel)
   - `samples/receipt_taj_cafe.png` (expected: ₹1000.50 Meals)
2. Find its `ContentDocumentId`:
   ```sql
   SELECT Id, Title FROM ContentDocument ORDER BY CreatedDate DESC LIMIT 5
   ```
3. Run Anonymous Apex (Developer Console → Debug → Open Execute Anonymous Window):
   ```apex
   OncoGlobal_ParseReceiptImage.Request r = new OncoGlobal_ParseReceiptImage.Request();
   r.contentDocumentId = '069XXXXXXXXXXXXXX'; // paste your ContentDocumentId
   r.visitContext = 'Visit to Dr Mehta, Apollo Bandra';

   List<OncoGlobal_ParseReceiptImage.Response> resp =
       OncoGlobal_ParseReceiptImage.parseReceipt(
           new List<OncoGlobal_ParseReceiptImage.Request>{ r }
       );

   System.debug('Confirmation: ' + resp[0].confirmationMessage);
   System.debug('Expense Id : ' + resp[0].expenseId);
   System.debug('Raw JSON   : ' + resp[0].parsedJson);
   ```
4. Expected debug output for the Ola receipt:
   ```
   Confirmation: ₹379.06 Travel logged from receipt ✅
   Expense Id : a04XXXXXXXXXXXX
   Raw JSON   : { "document": { ... "supplier_name": {"value": "Ola"}, "total_amount": {"value": 379.06}, ... } }
   ```
5. Verify the new `Expense__c`:
   ```sql
   SELECT Id, Amount__c, Category__c, Merchant__c, Expense_Date__c, OCR_Confidence__c, Notes__c
   FROM Expense__c ORDER BY CreatedDate DESC LIMIT 1
   ```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `HTTP 401 Unauthorized` | Wrong / missing API key | Re-check step 5 (Authentication Parameter `apiKey`) and step 7 (custom header value) |
| `Mindee callout failed: Unauthorized endpoint` | Permission set not assigned to user | Step 8 — assign `OncoGlobal Mindee Access` to running user |
| `HTTP 404 Not Found` | Wrong path | Verify Apex constant `MINDEE_PATH` is `/v1/products/mindee/expense_receipts/v5/predict` |
| `Invalid file format` | Mindee rejects the image | Use PNG / JPG / PDF (sample files are PNG, both supported) |
| Empty `parsedJson` | Callout timed out | Increase timeout in Apex or check Mindee dashboard for status |
