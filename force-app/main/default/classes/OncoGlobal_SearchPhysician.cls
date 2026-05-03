public with sharing class OncoGlobal_SearchPhysician {

    public class Request {
        @InvocableVariable(label='Search Query' description='Physician name, NPI, or clinic name to search for')
        public String searchQuery;

        @InvocableVariable(label='Record Id' description='Optional: HealthcareProvider Id for direct lookup (skips search)')
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Physician Id')
        public String physicianId;

        @InvocableVariable(label='Clinic Id')
        public String clinicId;

        @InvocableVariable(label='Match Results')
        public String matchResults;
    }

    @InvocableMethod(
        label='OncoGlobal Search Physician'
        description='Searches HealthcareProvider (Name, NPI) and HealthcareFacility (Name) and returns up to 5 formatted matches.'
    )
    public static List<Response> search(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(processOne(req));
        }
        return results;
    }

    private static Response processOne(Request req) {
        Response resp = new Response();

        if (String.isNotBlank(req.recordId)) {
            List<HealthcareProvider> providers = [
                SELECT Id, Name, NPI__c
                FROM HealthcareProvider
                WHERE Id = :req.recordId
                LIMIT 1
            ];
            if (!providers.isEmpty()) {
                HealthcareProvider p = providers[0];
                resp.physicianId = p.Id;
                resp.matchResults = '1. ' + p.Name + (String.isNotBlank(p.NPI__c) ? ' (NPI: ' + p.NPI__c + ')' : '');
                resp.clinicId = getPrimaryFacilityId(p.Id);
            } else {
                resp.matchResults = 'No physician found for the provided Id.';
            }
            return resp;
        }

        if (String.isBlank(req.searchQuery) || req.searchQuery.length() < 2) {
            resp.matchResults = 'Please provide at least 2 characters to search.';
            return resp;
        }

        String term = req.searchQuery;
        List<List<SObject>> searchResults = [
            FIND :term IN ALL FIELDS
            RETURNING
                HealthcareProvider(Id, Name, NPI__c LIMIT 5),
                HealthcareFacility(Id, Name LIMIT 5)
        ];

        List<HealthcareProvider> providers = (List<HealthcareProvider>) searchResults[0];
        List<HealthcareFacility> facilities = (List<HealthcareFacility>) searchResults[1];

        if (providers.isEmpty() && facilities.isEmpty()) {
            resp.matchResults = 'No matching physicians or clinics found. Please try a different name or NPI.';
            return resp;
        }

        List<String> lines = new List<String>();
        Integer idx = 1;
        for (HealthcareProvider p : providers) {
            String line = idx + '. Dr. ' + p.Name +
                (String.isNotBlank(p.NPI__c) ? ' (NPI: ' + p.NPI__c + ')' : '');
            lines.add(line);
            idx++;
        }
        for (HealthcareFacility f : facilities) {
            lines.add(idx + '. [Clinic] ' + f.Name);
            idx++;
        }

        if (!providers.isEmpty()) {
            resp.physicianId = providers[0].Id;
            resp.clinicId = getPrimaryFacilityId(providers[0].Id);
        } else if (!facilities.isEmpty()) {
            resp.clinicId = facilities[0].Id;
        }

        resp.matchResults = String.join(lines, '\n');
        return resp;
    }

    private static Id getPrimaryFacilityId(Id providerId) {
        List<HealthcarePractitionerFacility> primary = [
            SELECT HealthcareFacilityId
            FROM HealthcarePractitionerFacility
            WHERE HealthcareProviderId = :providerId AND IsPrimaryFacility = true
            LIMIT 1
        ];
        if (!primary.isEmpty()) return primary[0].HealthcareFacilityId;
        List<HealthcarePractitionerFacility> fallback = [
            SELECT HealthcareFacilityId
            FROM HealthcarePractitionerFacility
            WHERE HealthcareProviderId = :providerId
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0].HealthcareFacilityId;
    }
}
