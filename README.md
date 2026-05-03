# Onco Global Post-Visit Log Agent — Hackathon Submission

## Project Description (paste into "Description" field)

**Onco Global Post-Visit Log Agent** is a mobile-first, AI-powered Agentforce assistant that automates the entire post-visit administrative workflow for Onco Global — a cancer-care hospital network in India with 22 field sales executives visiting referring physicians daily across 10+ hospitals.

Today these reps log visits, expenses, and follow-ups in spreadsheets after their visits — losing 60-90 minutes per day to admin. The agent eliminates that completely. A rep can dictate (or text) a visit summary, snap a photo of a cab/restaurant receipt over WhatsApp, and get a fully-structured Visit Log, follow-up Tasks, and Expense records created in Salesforce Health Cloud — in under 30 seconds — without leaving the conversation.

**Core capabilities:**

- **Voice-to-Visit-Log**: Rep dictates "Met Dr. Mehta at Apollo Bandra. Discussed our radiation therapy program. She's interested in head & neck referrals. Wants the brochure. Lunch next Thursday." The agent uses an Einstein Prompt Template to extract structured fields (topics, sentiment, referral interest, specialties, requested materials, follow-ups), confirms with the rep, and creates a `Visit_Log__c` record linked to the `HealthcareProvider` and `HealthcareFacility`.
- **Auto follow-up tasks**: A second prompt template extracts tasks (subject, due date, type, priority) from the visit. The agent presents each one for confirmation, then creates `Task` records linked to the visit log.
- **WhatsApp receipt OCR**: The rep sends a photo of a receipt over WhatsApp. An Apex `@InvocableMethod` calls Mindee Receipt Parser v2 (via Named Credential), gets back structured JSON (merchant, total, date, line items, confidence), and creates an `Expense__c` record linked to the current visit. End-to-end takes ~3 seconds.
- **Pre-visit insights & talking points**: Before a visit, the rep asks "Tell me about Dr. Mehta." Apex pulls the last visit, 90-day referral count and trend, days-since-visit, and open tasks; a third prompt template generates 2-3 personalised talking points.
- **Multi-modal Agentforce orchestration**: A main agent routes intent to 5 subagents (Visit Note Logging, Automated Task Creation, Expense Management, Physician Relationship Insights, WhatsApp Digital Engagement) plus utility topics for FAQ / off-topic / ambiguous handling.

The architecture is 100% Salesforce-native for orchestration: Health Cloud objects (`HealthcareProvider`, `HealthcareFacility`, `HealthcarePractitionerFacility`, `Referral`) for the data model, Agentforce for the conversational agent, Einstein Prompt Templates (`einstein_gpt__flex` type) for AI structuring, Autolaunched Flows for record creation, Apex `@InvocableMethod` for SOSL search and aggregate insights queries. The only external dependency is Mindee Receipt Parser for image OCR (free tier, accessed via Named Credential — Salesforce's recommended pattern for external services).

---

## Products, Features, Tools, and APIs Used

**Salesforce Platform:**
- Salesforce Health Cloud (Provider edition) — `HealthcareProvider`, `HealthcareFacility`, `HealthcarePractitionerFacility`, `Referral` standard objects
- Custom objects: `Visit_Log__c` (15 fields), `Expense__c` (10 fields)
- Custom field on `HealthcareProvider`: `Onco_Tag__c` (multi-select picklist for tier/focus tagging), `NPI__c` (unique external ID)
- Salesforce Lightning Platform — Lightning App Builder, Mobile App
- Salesforce DX (sf CLI) — source-driven deployment (API v66.0)

**Agentforce / Einstein:**
- **Agentforce** — main agent (`OncoGlobal_Post_Visit_Log_Agent`) with 5 business subagents + 3 utility topics
- **Atlas Reasoning Engine** — agent planner / orchestration
- **Einstein Prompt Builder** — 5 prompt templates (`einstein_gpt__flex`) targeting `sfdc_ai__DefaultGPT5Mini`:
  - `OncoGlobal_ParseVisitNotesTemplate`
  - `OncoGlobal_ExtractFollowUpTasksTemplate`
  - `OncoGlobal_GenerateTalkingPointsTemplate`
  - `OncoGlobal_ParseExpensesTemplate`
  - `OncoGlobal_ParseReceiptImageTemplate`
- **Einstein Trust Layer** — secure LLM invocation with sfdc-managed credentials

**Apex:**
- `OncoGlobal_SearchPhysician` — `@InvocableMethod` with SOSL across HealthcareProvider/HealthcareFacility
- `OncoGlobal_GetPhysicianInsights` — `@InvocableMethod` with `COUNT()` aggregate SOQL for referral trend (current 90-day vs prior 90-day window) and Visit_Log + Task subqueries
- `OncoGlobal_ParseReceiptImage` — `@InvocableMethod` HTTP callout via Named Credential, multipart-form-data POST, async enqueue + poll pattern, JSON parsing

**Autolaunched Flows:**
- `OncoGlobal_CreateVisitLogRecord` — creates `Visit_Log__c` with all extracted fields
- `OncoGlobal_CreateFollowUpTask` — creates `Task` linked to Visit Log
- `OncoGlobal_LogExpenseRecord` — creates `Expense__c` for text-parsed expenses

**External Services:**
- **Mindee Receipt Parser v2** (`api-v2.mindee.net`) — receipt image OCR with structured field extraction (merchant, total, date, line items, confidence). Free tier (250 receipts/month). Accessed via Salesforce Named Credential + External Credential pattern.

**Salesforce APIs / Patterns:**
- Tooling API (EntityDefinition, FieldDefinition, FlowDefinitionView)
- Metadata API (deploy/retrieve)
- `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate` (probed for multimodal — see "Further Improvements")
- Named Credentials with External Credential principal + custom header merge fields (`{!$Credential.NC_Mindee_External.apiKey}`)
- SOSL `FIND :term IN ALL FIELDS RETURNING ...`

**Data:**
- Sample receipt PNGs generated programmatically (Python + Pillow) for testing
- INR-denominated, Indian-context test data (Ola cab, Taj Cafe with GST/CGST/SGST, etc.)

---

## Further Improvements

Given more time:

1. **Salesforce-native multimodal OCR** — replace Mindee with the in-Salesforce `ConnectApi` multimodal flow once `WrappedValue.value = ContentVersion` reliably attaches files to the LLM payload from Apex (we probed this; the prompt template renders the file's `Title` as text but doesn't auto-attach bytes when invoked from Apex — this works in Prompt Builder UI but the API-level mechanism for file attachment to template invocations needs to mature). Eliminating Mindee removes the only external dependency.
2. **Data Cloud unified physician profile** — build the spec'd DMOs (`Total_Referrals_LTD`, `Engagement_Tier`, `Avg_Sentiment_Score`) and segments (`High_Value_Unvisited_Physicians`, `Declining_Referrers`) for sales-manager dashboards. Hooks already in place — `Onco_Tag__c` multi-select on HealthcareProvider, structured `Visit_Log__c` + `Referral` schema.
3. **Voice-first WhatsApp** — voice-note transcription (Apex callout to Whisper or sfdc-native ASR when GA) so reps can speak, not type, on the move.
4. **Running expense total per visit** — `LogExpense` flow currently returns per-record confirmation; add an aggregate query so the agent says "₹380 logged ✅ — visit total ₹630". Single SOQL change.
5. **Pre-visit nudge** — scheduled Apex / Flow that runs every morning, identifies physicians the rep is visiting today (calendar integration), and pre-warms `GenerateTalkingPoints` so the briefing arrives in WhatsApp before the visit starts.
6. **Field service / route optimization** — combine visit logs with map-based clinic clustering to suggest the next-best physician to visit nearby.
7. **Permission set + agent user provisioning** — automate the per-rep permission grant (currently we have `OncoGlobal_Mindee_Access` for the Mindee credential; productionising means scripting this for all 22 reps).
8. **Telemetry** — Custom Object `Agent_Conversation__c` capturing intent, action, latency, success — feeding a Sales Manager dashboard for "what % of visits get logged within 30 min?" KPIs.
9. **Knowledge grounding** — populate Salesforce Knowledge with Onco Global oncology brochures, then `streamKnowledgeSearch` answers product questions on the fly (current `GeneralFAQ` topic is wired but knowledge base is empty in this hackathon org).

---

## Repository Structure (for reviewer context)

```
force-app/main/default/
  ├─ objects/
  │   ├─ Visit_Log__c/        # Custom object + 15 fields
  │   ├─ Expense__c/          # Custom object + 10 fields
  │   └─ HealthcareProvider/  # Onco_Tag__c (multi-select) + NPI__c
  ├─ flows/
  │   ├─ OncoGlobal_CreateVisitLogRecord.flow-meta.xml
  │   ├─ OncoGlobal_CreateFollowUpTask.flow-meta.xml
  │   └─ OncoGlobal_LogExpenseRecord.flow-meta.xml
  ├─ classes/
  │   ├─ OncoGlobal_SearchPhysician.cls
  │   ├─ OncoGlobal_GetPhysicianInsights.cls
  │   └─ OncoGlobal_ParseReceiptImage.cls   # Mindee callout
  └─ genAiPromptTemplates/
      ├─ OncoGlobal_ParseVisitNotesTemplate
      ├─ OncoGlobal_ExtractFollowUpTasksTemplate
      ├─ OncoGlobal_GenerateTalkingPointsTemplate
      ├─ OncoGlobal_ParseExpensesTemplate
      └─ OncoGlobal_ParseReceiptImageTemplate

docs/
  ├─ agent_spec.yaml                      # Agentforce agent definition
  ├─ PHASE_3C_MINDEE_SETUP.md             # Named Credential setup
  ├─ PHASE_5_AGENT_BUILDER_SETUP.md       # Agent Builder UI walkthrough
  └─ SUBMISSION.md                        # This file

samples/
  ├─ generate_receipts.py
  ├─ receipt_ola_cab.png      # Test: ₹379.06 → Travel
  └─ receipt_taj_cafe.png     # Test: ₹1000.50 → Meals
```
