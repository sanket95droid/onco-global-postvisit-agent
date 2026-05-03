# Phase 5 — Agentforce Agent Setup

This guide wires the Onco Global Post-Visit Log Agent in Agent Builder. Everything it needs (flows, Apex actions, prompt templates) is already deployed.

## Prerequisites — verify before starting

Run these once in Developer Console (or via the org browser) to confirm Phase 1–4 components are live:

```sql
-- Should return 5 rows
SELECT DeveloperName FROM GenAiPromptTemplate WHERE DeveloperName LIKE 'OncoGlobal_%' ORDER BY DeveloperName

-- Should return 3 rows
SELECT ApiName FROM FlowDefinitionView WHERE ApiName LIKE 'OncoGlobal_%' AND IsActive = true

-- Should return 3 rows
SELECT Name FROM ApexClass WHERE Name LIKE 'OncoGlobal_%' ORDER BY Name
```

Expected count: 5 + 3 + 3 = 11 components.

---

## Step 1 — Create the agent

1. **Setup** → Quick Find: `Agents` → click **Agents** (under Agentforce)
2. Click **New Agent**
3. Pick template:
   - If your org has a "Custom" or "Internal Copilot" template, use it
   - Otherwise pick **Agentforce Service Agent** then customise (we'll override topics)
4. Click **Next**
5. Fill in:
   - **Name**: `Post-Visit Log Agent`
   - **API Name**: `OncoGlobalPostVisitAgent`
   - **Description**: `AI assistant for Onco Global's field sales executives. Automates post-visit logging, follow-up task creation, expense management, and physician relationship insights. Available via Salesforce Mobile and WhatsApp.`
   - **Company / Role**: Sales Operations
   - **Tone**: Professional, concise, mobile-first (replies under 160 chars where possible)
6. Click **Save** — this creates the agent skeleton.

You'll land on the agent's overview page. Leave the default planner ("Atlas Reasoning Engine" / current default).

---

## Step 2 — Replace default topics with our 7 topics

Default agents come with placeholder topics (e.g. "General CRM"). Delete them, then add ours.

For each of the 7 topics below: click **+ New Topic** → fill in **Topic Label**, **Classification Description**, and **Scope/Reasoning Instructions** → save → then add the listed Actions.

### Topic 1 — `Service Customer Verification`

| Field | Value |
|---|---|
| **Topic Label** | Service Customer Verification |
| **API Name** | `Service_Customer_Verification` |
| **Classification Description** | Verifies the identity of the sales executive at conversation start before any record-creating action. Triggered when the user has not yet been verified in this session. |
| **Scope** | Verify only. Don't perform any other action until verification succeeds. If verification fails 3 times, end the session politely. |
| **Instructions** | Ask for the user's email or username, send a verification code via the SendEmailVerificationCode standard action, then ask them to enter the code and validate via VerifyCustomer. Once verified, hand off to the appropriate next topic. Never reveal codes to the user. |

**Actions to add** (Library picker → "Standard"):
- `streamKnowledgeSearch` — *no, not for this topic*
- `Send Email Verification Code` (standard)
- `Verify Customer / Code` (standard — usually `SvcCopilotTmpl__VerifyCode`)

> If your org doesn't have these standard actions visible, skip Topic 1 for the MVP — you can verify identity simply by logged-in Salesforce session.

### Topic 2 — `Visit Note Logging`

| Field | Value |
|---|---|
| **Topic Label** | Visit Note Logging |
| **API Name** | `Visit_Note_Logging` |
| **Classification Description** | Logs a sales executive's visit to a referring physician. Triggered by phrases like "I just visited", "I met with Dr.", "log a visit", "met at the clinic". |
| **Scope** | Capture the visit accurately. Never skip the physician identification step. Always show the structured summary back to the user before saving. |
| **Instructions** | (1) Identify the physician using SearchPhysician — confirm the match with the user before proceeding. (2) Ask the user to dictate or type their visit notes. (3) Pass the raw notes to ParseVisitNotes prompt template — it returns structured JSON. (4) Show the structured summary (topics, sentiment, referral interest) to the user and ask "Save?". (5) On confirmation, call CreateVisitLog flow. (6) After saving, ask if the user wants follow-up tasks created (hand off to Automated Task Creation topic). |

**Actions to add** (Library picker → "Custom"):
- **Apex action**: `OncoGlobal_SearchPhysician` → `OncoGlobal Search Physician`
- **Prompt Template action**: `OncoGlobal_ParseVisitNotesTemplate` → `OncoGlobal Parse Visit Notes`
- **Flow action**: `OncoGlobal_CreateVisitLogRecord` → `OncoGlobal Create Visit Log Record`

### Topic 3 — `Automated Task Creation`

| Field | Value |
|---|---|
| **Topic Label** | Automated Task Creation |
| **API Name** | `Automated_Task_Creation` |
| **Classification Description** | Creates Salesforce Tasks from follow-up commitments mentioned during a visit. Triggered after a visit is logged or by phrases like "create a task", "remind me", "follow up next week". |
| **Scope** | Only create tasks the user has confirmed. Never silently create multiple tasks. |
| **Instructions** | (1) If continuing from Visit Note Logging, take the followUpActions text from the saved Visit Log. (2) Pass to ExtractFollowUpTasks prompt template — returns a JSON array of tasks (subject, dueDate, priority, taskType, description). (3) Present each task to the user one by one, ask "Create this?". (4) For each confirmed task, call CreateTask flow with the relevant fields. (5) Always link tasks to the Visit Log Id and run as the current sales rep. |

**Actions to add**:
- **Prompt Template**: `OncoGlobal_ExtractFollowUpTasksTemplate`
- **Flow**: `OncoGlobal_CreateFollowUpTask`

### Topic 4 — `Expense Management`

| Field | Value |
|---|---|
| **Topic Label** | Expense Management |
| **API Name** | `Expense_Management` |
| **Classification Description** | Logs visit-related expenses. Triggered by text like "log my cab", "₹", "expense", or by an inbound message containing a receipt image. |
| **Scope** | One Expense__c record per receipt image; one or more per text input. Always link to the most recent Visit Log if one exists in the session. |
| **Instructions** | (1) **If the user attached a receipt image** (ContentDocument): call ParseReceiptImage Apex action with the contentDocumentId — it OCRs via Mindee and creates the Expense automatically. Show the result to the user. (2) **If the user sent text** (e.g. "₹380 Ola from Apollo to BKC"): pass to ParseExpenses prompt template, get structured JSON, show to user for confirmation, then call LogExpense flow for each item. (3) Always set Sales_Rep__c to current user, link to relatedVisitLogId if known. |

**Actions to add**:
- **Apex**: `OncoGlobal_ParseReceiptImage`
- **Prompt Template**: `OncoGlobal_ParseExpensesTemplate`
- **Flow**: `OncoGlobal_LogExpenseRecord`

### Topic 5 — `Physician Relationship Insights`

| Field | Value |
|---|---|
| **Topic Label** | Physician Relationship Insights |
| **API Name** | `Physician_Relationship_Insights` |
| **Classification Description** | Surfaces physician relationship history for pre-visit preparation. Triggered by "tell me about Dr.", "before I visit", "what's our history with", "talking points for". |
| **Scope** | Read-only. Never create records in this topic. |
| **Instructions** | (1) Identify the physician via SearchPhysician. (2) Call GetPhysicianInsights Apex action — returns JSON with last visit date, sentiment, referral count and trend, open tasks, days since last visit. (3) Pass relevant fields to GenerateTalkingPoints prompt template (consolidating into the 5 input slots: physicianName, specialty, lastVisitContext, referralActivity, openItemsContext). (4) Show the talking points to the user as a numbered list. |

**Actions to add**:
- **Apex**: `OncoGlobal_SearchPhysician`
- **Apex**: `OncoGlobal_GetPhysicianInsights`
- **Prompt Template**: `OncoGlobal_GenerateTalkingPointsTemplate`

### Topic 6 — `WhatsApp Digital Engagement`

| Field | Value |
|---|---|
| **Topic Label** | WhatsApp Digital Engagement |
| **API Name** | `WhatsApp_Digital_Engagement` |
| **Classification Description** | Handles WhatsApp-channel-specific conversational patterns. Activated when the conversation is on the WhatsApp Messaging Channel. |
| **Scope** | Mobile-first, terse responses. Use emojis sparingly (✅ ❌ ⚠️). Hand off image attachments to Expense Management; hand off voice notes to Visit Note Logging. |
| **Instructions** | Detect intent from the inbound message and route to the appropriate topic. Keep all responses under 160 characters. If the user sends an image, treat it as a receipt unless context suggests otherwise. If the user sends a voice note, prompt for transcription text first. |

**Actions to add** (re-uses actions from other topics — Agent Builder allows action sharing):
- All actions from Topics 2, 3, 4

### Topic 7 — `General FAQ`

| Field | Value |
|---|---|
| **Topic Label** | General FAQ |
| **API Name** | `General_FAQ` |
| **Classification Description** | Answers general questions about Onco Global, the agent's capabilities, or the sales process. Triggered when none of the other topics match. |
| **Scope** | Knowledge-grounded only. Don't make up answers. |
| **Instructions** | Use the standard knowledge search action to find relevant Onco Global articles. If no answer is found, say "I don't have that information — please contact your manager." |

**Actions to add**:
- Standard: `streamKnowledgeSearch` (or `AnswerQuestionsWithKnowledge`)

---

## Step 3 — Test in the simulator

In the agent's right-hand pane, click **Conversation Preview** and run this script:

| Turn | You say | Expected behaviour |
|---|---|---|
| 1 | `Hi` | Welcome message |
| 2 | `I just visited Dr. Priya Mehta at Apollo Clinic Bandra` | Triggers **Visit Note Logging**. Calls `OncoGlobal_SearchPhysician` to confirm the match. (You'll need a `HealthcareProvider` record named "Priya Mehta" first — create one if testing.) |
| 3 | `Yes, that's the one` | Asks for visit notes. |
| 4 | `We discussed the new radiation therapy program. She is very interested in referring head and neck cancer cases. Wants the oncology brochure. Follow up next Thursday for a lunch meeting.` | Calls `OncoGlobal_ParseVisitNotesTemplate`, shows structured summary (topics, sentiment, referral interest), asks "Save?" |
| 5 | `Yes, log it` | Calls `OncoGlobal_CreateVisitLogRecord`, returns visitLogId. Asks if user wants follow-up tasks. |
| 6 | `Yes` | Calls `OncoGlobal_ExtractFollowUpTasksTemplate`, lists each extracted task. |
| 7 | `Yes` (to each) | Creates Tasks via `OncoGlobal_CreateFollowUpTask`. |
| 8 | `Also log my cab expense, ₹380 Ola from clinic to office` | Triggers **Expense Management**. Calls `OncoGlobal_ParseExpensesTemplate`. Shows confirmation. |
| 9 | `Confirm` | Creates Expense__c via `OncoGlobal_LogExpenseRecord`. |
| 10 | *Upload* `samples/receipt_taj_cafe.png` | Triggers **Expense Management** with image. Calls `OncoGlobal_ParseReceiptImage` Apex. Returns "₹1000.50 Meals logged from receipt ✅". |
| 11 | `Tell me about Dr Mehta before my next visit` | Triggers **Physician Relationship Insights**. Calls insights Apex + talking points template. |

---

## Step 4 — Activate

1. From the agent's overview page, click **Activate**
2. Confirm the agent is now usable from:
   - Agent Builder Preview (always)
   - Salesforce Mobile App (Utility bar) — once published to a Lightning App
   - WhatsApp Messaging Channel — Phase 6 setup (separate guide)

---

## Step 5 (stretch) — Retrieve agent metadata for source

After the agent is working, commit it to source for reproducibility:

```bash
sf project retrieve start \
  --metadata "GenAiApplication:OncoGlobalPostVisitAgent" \
  --metadata "GenAiPlannerBundle:*" \
  --metadata "GenAiPlugin:*" \
  --metadata "GenAiFunction:*" \
  --target-org awtOrg
```

This pulls the topic and action definitions into `force-app/main/default/`. Add to git for full reproducibility.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Action not visible in Library picker | Apex/Flow not exposed properly | Ensure Apex `@InvocableMethod` annotation present (we have these) and Flow has `<environments>Default</environments>` |
| "User does not have permission" when invoking action | Missing Permission Set | Assign permission set covering Visit_Log__c, Expense__c, Apex classes, Flows, External Credential `NC_Mindee_External` |
| Agent picks wrong topic | Classification Description too vague | Make trigger phrases more specific in the topic's Classification Description |
| Receipt image action errors | Mindee NC misconfigured | Re-verify [PHASE_3C_MINDEE_SETUP.md](PHASE_3C_MINDEE_SETUP.md) steps 6-8 |
| Prompt template returns garbage | Inputs not mapped from agent context | In Agent Builder action config, map each input parameter to a session variable or upstream output |
