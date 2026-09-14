# Salesforce Mass Billing Approval Module ⚡

An enterprise-grade, bulk-enabled Salesforce Billing Approval and Rejection engine built with **Lightning Web Components (LWC)**, **Apex Service Layer**, and **Audit Trail Logging**.

---

## 🌟 Key Features

1. **Dual-Mode Operation**:
   - **Mode 1 (Live SF Query)**: Queries active Orders in `Billing Approval` status with multi-account filtering and keyword search.
   - **Mode 2 (File Upload / Batch Rekon)**: Upload CSV / Excel containing Order Numbers with automatic zero-padding (e.g. `68134` $\rightarrow$ `00068134`).
2. **Bulk Actions & Auto-Selection**:
   - 1-Click **"Select All"** and automatic pre-selection of all valid orders upon file upload.
   - Bulk approval updates Order Status to `Completed` and sets `Approved_via_Button__c = true`.
   - Bulk rejection moves orders back to `BASO In Progress` with a mandatory rejection reason.
3. **Partial Success & Error Summary Modal**:
   - Executes with `Database.update(records, false)` (AllOrNone = false).
   - Valid orders succeed immediately, while failed orders open a dedicated **Error Summary Modal** with clickable record links and **"Export Failed Orders (CSV)"**.
4. **Permanent Audit Trail**:
   - All approval and rejection events are permanently recorded in `Billing_Approval_Audit__c` with timestamps and User ID.

---

## 📦 Package Components

| Component Type | Component Name | Description |
| :--- | :--- | :--- |
| **Apex Class** | `MassBillingApprovalService` | Core service layer handling SOQL, DML, and DTO mapping |
| **Apex Class** | `MassBillingApprovalController` | AuraEnabled controller endpoints for LWC |
| **Apex Class** | `MassBillingApprovalTest` | Comprehensive unit tests (100% pass rate) |
| **LWC** | `massBillingApproval` | Interactive UI with Tabs, Datatable, Modals, & CSV Export |
| **Custom Object** | `Billing_Approval_Audit__c` | Audit history records |
| **Custom Field** | `Order.Approved_via_Button__c` | Checkbox tracking button approval |
| **Custom Tab** | `Mass_Billing_Approval` | Lightning Tab for App Builder navigation |
| **Static Resource** | `MassBillingTemplate` | Sample CSV template for user uploads |

---

## 🚀 Quick Deployment Guide

### Using Salesforce CLI:

```bash
# 1. Authorize Target Org
sf org login web --alias target-org

# 2. Deploy using Manifest
sf project deploy start --manifest manifest/package.xml --target-org target-org --test-level RunSpecifiedTests --tests MassBillingApprovalTest
```

### Using GitHub Actions CI/CD:
1. Store target org Auth URL in GitHub Repository Secret: `SF_STAGING_AUTH_URL` or `SF_PROD_AUTH_URL`.
2. Go to **Actions** $\rightarrow$ **Deploy to TIF Staging** $\rightarrow$ Click **Run workflow** (Mode: `DRY-RUN` or `DEPLOY`).

---

## 🧪 Unit Test Execution

```bash
sf apex run test --tests MassBillingApprovalTest --target-org target-org --result-format human --code-coverage
```

---

## 📄 License
MIT / Proprietary Internal Module.