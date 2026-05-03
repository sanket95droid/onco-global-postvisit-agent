public with sharing class OncoGlobal_GetPhysicianInsights {

    public class Request {
        @InvocableVariable(required=true label='Physician Id' description='HealthcareProvider Id')
        public String physicianId;

        @InvocableVariable(label='Clinic Id' description='Optional HealthcareFacility Id')
        public String clinicId;
    }

    public class Response {
        @InvocableVariable public String lastVisitDate;
        @InvocableVariable public String lastVisitSummary;
        @InvocableVariable public String lastVisitSentiment;
        @InvocableVariable public String visitsLast90Days;
        @InvocableVariable public String referralCount;
        @InvocableVariable public String referralTrend;
        @InvocableVariable public String openTasksCount;
        @InvocableVariable public String openTasksSummary;
        @InvocableVariable public String daysSinceLastVisit;
        @InvocableVariable public String insightsSummaryJson;
    }

    @InvocableMethod(
        label='OncoGlobal Get Physician Insights'
        description='Returns visit history, referral trend, and open tasks for a physician.'
    )
    public static List<Response> getInsights(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(buildInsights(req.physicianId));
        }
        return results;
    }

    private static Response buildInsights(String physicianId) {
        Response r = new Response();
        r.lastVisitDate = '';
        r.lastVisitSummary = '';
        r.lastVisitSentiment = '';
        r.daysSinceLastVisit = '';
        r.visitsLast90Days = '0';
        r.referralCount = '0';
        r.referralTrend = 'Stable →';
        r.openTasksCount = '0';
        r.openTasksSummary = '';

        if (String.isBlank(physicianId)) {
            r.lastVisitSummary = 'No physicianId provided.';
            r.insightsSummaryJson = '{}';
            return r;
        }

        List<Visit_Log__c> latest = [
            SELECT Id, Visit_Date__c, Visit_Summary__c, Physician_Sentiment__c
            FROM Visit_Log__c
            WHERE Physician__c = :physicianId
            ORDER BY Visit_Date__c DESC
            LIMIT 1
        ];
        if (!latest.isEmpty()) {
            Visit_Log__c v = latest[0];
            if (v.Visit_Date__c != null) {
                r.lastVisitDate = v.Visit_Date__c.format('dd MMM yyyy');
                Long diffMs = DateTime.now().getTime() - v.Visit_Date__c.getTime();
                r.daysSinceLastVisit = String.valueOf(diffMs / (1000L * 60L * 60L * 24L));
            }
            r.lastVisitSummary = v.Visit_Summary__c == null ? '' : v.Visit_Summary__c;
            r.lastVisitSentiment = v.Physician_Sentiment__c == null ? '' : v.Physician_Sentiment__c;
        } else {
            r.lastVisitSummary = 'No prior visits.';
        }

        Integer visits90 = [
            SELECT COUNT() FROM Visit_Log__c
            WHERE Physician__c = :physicianId AND Visit_Date__c = LAST_N_DAYS:90
        ];
        r.visitsLast90Days = String.valueOf(visits90);

        Integer refsCurrent = [
            SELECT COUNT() FROM Referral
            WHERE ProviderId = :physicianId AND CreatedDate = LAST_N_DAYS:90
        ];
        Integer refsPrev = [
            SELECT COUNT() FROM Referral
            WHERE ProviderId = :physicianId
              AND CreatedDate >= LAST_N_DAYS:180
              AND CreatedDate < LAST_N_DAYS:90
        ];
        r.referralCount = String.valueOf(refsCurrent);
        if (refsCurrent > refsPrev) r.referralTrend = 'Increasing ↑';
        else if (refsCurrent < refsPrev) r.referralTrend = 'Declining ↓';
        else r.referralTrend = 'Stable →';

        List<Task> tasks = [
            SELECT Id, Subject FROM Task
            WHERE WhatId IN (SELECT Id FROM Visit_Log__c WHERE Physician__c = :physicianId)
              AND Status != 'Completed'
            LIMIT 5
        ];
        r.openTasksCount = String.valueOf(tasks.size());
        List<String> subjects = new List<String>();
        for (Task t : tasks) subjects.add(t.Subject);
        r.openTasksSummary = String.join(subjects, ', ');

        Map<String, Object> jsonMap = new Map<String, Object>{
            'lastVisitDate' => r.lastVisitDate,
            'lastVisitSummary' => r.lastVisitSummary,
            'lastVisitSentiment' => r.lastVisitSentiment,
            'daysSinceLastVisit' => r.daysSinceLastVisit,
            'visitsLast90Days' => r.visitsLast90Days,
            'referralCount' => r.referralCount,
            'referralTrend' => r.referralTrend,
            'openTasksCount' => r.openTasksCount,
            'openTasksSummary' => r.openTasksSummary
        };
        r.insightsSummaryJson = JSON.serialize(jsonMap);
        return r;
    }
}
