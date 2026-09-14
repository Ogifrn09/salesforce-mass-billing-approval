public without sharing class MassBillingApprovalController {

    /**
     * @description MODE 1: Fetches live orders with Status = 'Billing Approval' and optional Multi-Customer filter
     */
    @AuraEnabled(cacheable=true)
    public static MassBillingApprovalService.ResponseWrapper getLiveOrders(List<Id> customerAccountIds, String searchKey) {
        return MassBillingApprovalService.getLiveOrders(customerAccountIds, searchKey);
    }

    /**
     * @description MODE 2: Queries and validates orders matching uploaded Order Numbers or SIDs
     */
    @AuraEnabled
    public static MassBillingApprovalService.ResponseWrapper getOrdersByUploadedKeys(List<String> orderNumbersOrSids) {
        return MassBillingApprovalService.getOrdersByUploadedKeys(orderNumbersOrSids);
    }

    /**
     * @description Executes bulk approval for selected orders
     */
    @AuraEnabled
    public static MassBillingApprovalService.ActionResultWrapper executeMassApprove(List<Id> orderIds) {
        return MassBillingApprovalService.processMassApproval(orderIds);
    }

    /**
     * @description Executes bulk rejection with reason for selected orders
     */
    @AuraEnabled
    public static MassBillingApprovalService.ActionResultWrapper executeMassReject(List<Id> orderIds, String rejectionReason) {
        return MassBillingApprovalService.processMassRejection(orderIds, rejectionReason);
    }

    /**
     * @description Retrieves available Customer Accounts (CA) for dropdown filter options
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCustomerAccountOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        List<Account> caList = [
            SELECT Id, Name 
            FROM Account 
            WHERE Account_Type__c = 'CA' 
               OR (RecordType.DeveloperName IN ('CA', 'OLO_Customer_Account') AND Account_Type__c NOT IN ('BA', 'SA'))
            ORDER BY Name ASC 
            LIMIT 500
        ];

        for (Account acc : caList) {
            Map<String, String> opt = new Map<String, String>();
            opt.put('label', acc.Name);
            opt.put('value', acc.Id);
            options.add(opt);
        }
        return options;
    }

    // Backward-compatibility wrapper for legacy references
    public class ReviewResultWrapper {
        @AuraEnabled public Integer totalPopulated { get; set; }
        @AuraEnabled public List<MassBillingApprovalService.OrderReviewDTO> reviewRecords { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isSuccess { get; set; }
    }

    @AuraEnabled
    public static ReviewResultWrapper populateAndGetOrders(Id customerAccountId) {
        ReviewResultWrapper result = new ReviewResultWrapper();
        result.totalPopulated = MassBillingApprovalService.populateReviewData(customerAccountId);
        result.message = 'Successfully loaded order data.';
        result.isSuccess = true;
        result.reviewRecords = new List<MassBillingApprovalService.OrderReviewDTO>();
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<MassBillingApprovalService.OrderReviewDTO> getReviewRecords(Id customerAccountId, String searchKey) {
        return new List<MassBillingApprovalService.OrderReviewDTO>();
    }
}