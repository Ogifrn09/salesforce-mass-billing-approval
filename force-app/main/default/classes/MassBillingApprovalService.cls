public without sharing class MassBillingApprovalService {

    public class OrderReviewDTO {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public String orderType { get; set; }
        @AuraEnabled public String statusOrder { get; set; }
        @AuraEnabled public String customerAccountId { get; set; }
        @AuraEnabled public String customerAccountName { get; set; }
        @AuraEnabled public String billingAccountId { get; set; }
        @AuraEnabled public String billingAccountName { get; set; }
        @AuraEnabled public Date billingDate { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public Decimal quoteListPrice { get; set; }
        @AuraEnabled public Decimal discount { get; set; }
        @AuraEnabled public Decimal total { get; set; }
        @AuraEnabled public String serviceId { get; set; }
        @AuraEnabled public String validationStatus { get; set; } // 'Valid', 'Invalid Status', 'Not Found'
        @AuraEnabled public String validationMessage { get; set; }
    }

    public class ResponseWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer validCount { get; set; }
        @AuraEnabled public Integer invalidCount { get; set; }
        @AuraEnabled public Decimal grandTotalAmount { get; set; }
        @AuraEnabled public List<OrderReviewDTO> records { get; set; }
    }

    public class FailedOrderDTO {
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public String customerAccountName { get; set; }
        @AuraEnabled public String billingAccountName { get; set; }
        @AuraEnabled public String serviceId { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }

    public class ActionResultWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public List<String> errorDetails { get; set; }
        @AuraEnabled public List<String> successfulOrderIds { get; set; }
        @AuraEnabled public List<FailedOrderDTO> failedOrders { get; set; }
    }

    /**
     * @description MODE 1: Live Query Orders with Status = 'Billing Approval' and optional Multi-Customer filter
     */
    public static ResponseWrapper getLiveOrders(List<Id> customerAccountIds, String searchKey) {
        ResponseWrapper res = new ResponseWrapper();
        res.records = new List<OrderReviewDTO>();
        res.grandTotalAmount = 0;

        try {
            String query = 'SELECT Id, OrderNumber, Type, Status, AccountId, Account.Name, ' +
                           'Bill_to_Account__c, Bill_to_Account__r.Name, ' +
                           'Billing_Start_Date__c, Billing_End_Date__c, ' +
                           'Service_ID__c, TotalAmount, ' +
                           '(SELECT Id, Product2.Name, SBQQ__QuotedListPrice__c, ListPrice, UnitPrice, ' +
                           'Total_Discount_Amt__c, TotalPrice, Total_Price_Custom__c ' +
                           'FROM OrderItems ORDER BY CreatedDate ASC) ' +
                           'FROM Order ' +
                           'WHERE Status = \'Billing Approval\' ';

            if (customerAccountIds != null && !customerAccountIds.isEmpty()) {
                query += 'AND AccountId IN :customerAccountIds ';
            }

            if (String.isNotBlank(searchKey)) {
                String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
                query += 'AND (OrderNumber LIKE :key OR Account.Name LIKE :key OR Service_ID__c LIKE :key) ';
            }

            query += 'ORDER BY CreatedDate DESC LIMIT 2000';

            List<Order> orderList = Database.query(query);
            for (Order ord : orderList) {
                OrderReviewDTO dto = mapOrderToDTO(ord, 'Valid', null);
                res.records.add(dto);
                res.grandTotalAmount += (dto.total != null ? dto.total : 0);
            }

            res.totalCount = res.records.size();
            res.validCount = res.records.size();
            res.invalidCount = 0;
            res.isSuccess = true;
            res.message = 'Successfully loaded ' + res.totalCount + ' order records.';
        } catch (Exception e) {
            res.isSuccess = false;
            res.message = 'Failed to load order data: ' + e.getMessage();
        }

        return res;
    }

    /**
     * @description MODE 2: Query and validate Orders matching uploaded Order Numbers
     */
    public static ResponseWrapper getOrdersByUploadedKeys(List<String> rawKeys) {
        ResponseWrapper res = new ResponseWrapper();
        res.records = new List<OrderReviewDTO>();
        res.grandTotalAmount = 0;
        res.validCount = 0;
        res.invalidCount = 0;

        if (rawKeys == null || rawKeys.isEmpty()) {
            res.isSuccess = false;
            res.message = 'File does not contain valid Order Numbers.';
            return res;
        }

        try {
            // Clean up inputs (remove duplicates, whitespaces, and auto-pad leading zeros if stripped by Excel)
            Set<String> cleanKeys = new Set<String>();
            for (String k : rawKeys) {
                if (String.isNotBlank(k)) {
                    String trimmed = k.trim();
                    cleanKeys.add(trimmed);
                    if (trimmed.isNumeric() && trimmed.length() < 8) {
                        cleanKeys.add(trimmed.leftPad(8, '0'));
                    }
                }
            }

            if (cleanKeys.isEmpty()) {
                res.isSuccess = false;
                res.message = 'No valid order numbers found in file.';
                return res;
            }

            // Query Orders strictly by OrderNumber
            String query = 'SELECT Id, OrderNumber, Type, Status, AccountId, Account.Name, ' +
                           'Bill_to_Account__c, Bill_to_Account__r.Name, ' +
                           'Billing_Start_Date__c, Billing_End_Date__c, ' +
                           'Service_ID__c, TotalAmount, ' +
                           '(SELECT Id, Product2.Name, SBQQ__QuotedListPrice__c, ListPrice, UnitPrice, ' +
                           'Total_Discount_Amt__c, TotalPrice, Total_Price_Custom__c ' +
                           'FROM OrderItems ORDER BY CreatedDate ASC) ' +
                           'FROM Order ' +
                           'WHERE OrderNumber IN :cleanKeys ' +
                           'ORDER BY CreatedDate DESC LIMIT 2000';

            List<Order> foundOrders = Database.query(query);
            Set<String> matchedKeys = new Set<String>();

            for (Order ord : foundOrders) {
                matchedKeys.add(ord.OrderNumber);
                if (ord.OrderNumber.isNumeric()) {
                    matchedKeys.add(ord.OrderNumber.leftPad(8, '0'));
                    matchedKeys.add(String.valueOf(Long.valueOf(ord.OrderNumber)));
                }

                Boolean isValidStatus = (ord.Status == 'Billing Approval');
                String statusMsg = isValidStatus ? null : 'Current order status (' + ord.Status + ') is not Billing Approval';
                String valStatus = isValidStatus ? 'Valid' : 'Warning';

                OrderReviewDTO dto = mapOrderToDTO(ord, valStatus, statusMsg);
                res.records.add(dto);

                if (isValidStatus) {
                    res.validCount++;
                    res.grandTotalAmount += (dto.total != null ? dto.total : 0);
                } else {
                    res.invalidCount++;
                }
            }

            // Check keys not found in Salesforce (avoid reporting unpadded key if padded key matched)
            Set<String> reportedNotFound = new Set<String>();
            for (String key : cleanKeys) {
                String paddedKey = (key.isNumeric() && key.length() < 8) ? key.leftPad(8, '0') : key;
                if (!matchedKeys.contains(key) && !matchedKeys.contains(paddedKey) && !reportedNotFound.contains(paddedKey)) {
                    reportedNotFound.add(paddedKey);
                    res.invalidCount++;
                    OrderReviewDTO notFoundDto = new OrderReviewDTO();
                    notFoundDto.id = 'NF_' + paddedKey;
                    notFoundDto.orderNumber = paddedKey;
                    notFoundDto.statusOrder = '-';
                    notFoundDto.orderType = '-';
                    notFoundDto.customerAccountName = '-';
                    notFoundDto.billingAccountName = '-';
                    notFoundDto.productName = '-';
                    notFoundDto.quoteListPrice = 0;
                    notFoundDto.discount = 0;
                    notFoundDto.total = 0;
                    notFoundDto.serviceId = '-';
                    notFoundDto.validationStatus = 'Not Found';
                    notFoundDto.validationMessage = 'Order Number not found in Salesforce';
                    res.records.add(notFoundDto);
                }
            }

            res.totalCount = res.records.size();
            res.isSuccess = true;
            res.message = 'Completed processing file: ' + res.validCount + ' Valid Orders (Billing Approval), ' + 
                          res.invalidCount + ' Skipped/Invalid Orders.';
        } catch (Exception e) {
            res.isSuccess = false;
            res.message = 'Failed to process file upload: ' + e.getMessage();
        }

        return res;
    }

    /**
     * @description Mass Approves orders: Status -> 'Completed', Approved_via_Button__c -> true, creates Billing_Approval_Audit__c
     */
    public static ActionResultWrapper processMassApproval(List<Id> orderIds) {
        ActionResultWrapper result = new ActionResultWrapper();
        result.successCount = 0;
        result.failureCount = 0;
        result.errorDetails = new List<String>();
        result.successfulOrderIds = new List<String>();
        result.failedOrders = new List<FailedOrderDTO>();

        if (orderIds == null || orderIds.isEmpty()) {
            result.isSuccess = false;
            result.message = 'No orders selected to approve.';
            return result;
        }

        try {
            List<Order> ordersToUpdate = [
                SELECT Id, Status, OrderNumber, Account.Name, Bill_to_Account__r.Name, Service_ID__c, Approved_via_Button__c 
                FROM Order 
                WHERE Id IN :orderIds AND Status = 'Billing Approval'
            ];

            if (ordersToUpdate.isEmpty()) {
                result.isSuccess = false;
                result.message = 'No valid orders found with "Billing Approval" status.';
                return result;
            }

            for (Order ord : ordersToUpdate) {
                ord.Status = 'Completed';
                ord.Approved_via_Button__c = true;
            }

            Database.SaveResult[] srList = Database.update(ordersToUpdate, false);
            List<Billing_Approval_Audit__c> auditLogs = new List<Billing_Approval_Audit__c>();
            Datetime now = Datetime.now();
            Id currentUserId = UserInfo.getUserId();

            for (Integer i = 0; i < srList.size(); i++) {
                Database.SaveResult sr = srList[i];
                Order ord = ordersToUpdate[i];

                if (sr.isSuccess()) {
                    result.successCount++;
                    result.successfulOrderIds.add(ord.Id);
                    Billing_Approval_Audit__c audit = new Billing_Approval_Audit__c();
                    audit.Sales_Order__c = ord.Id;
                    audit.Action_Taken__c = 'Approved';
                    audit.Processed_By__c = currentUserId;
                    audit.Action_Date_Time__c = now;
                    auditLogs.add(audit);
                } else {
                    result.failureCount++;
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += (String.isBlank(errMsg) ? '' : '; ') + err.getMessage();
                    }
                    FailedOrderDTO failedDto = new FailedOrderDTO();
                    failedDto.orderId = ord.Id;
                    failedDto.orderNumber = ord.OrderNumber;
                    failedDto.customerAccountName = ord.Account != null ? ord.Account.Name : '-';
                    failedDto.billingAccountName = ord.Bill_to_Account__r != null ? ord.Bill_to_Account__r.Name : '-';
                    failedDto.serviceId = ord.Service_ID__c;
                    failedDto.errorMessage = errMsg;
                    result.failedOrders.add(failedDto);
                    result.errorDetails.add('Order ' + ord.OrderNumber + ': ' + errMsg);
                }
            }

            if (!auditLogs.isEmpty()) {
                Database.insert(auditLogs, false);
            }

            result.isSuccess = (result.successCount > 0);
            result.message = 'Successfully approved ' + result.successCount + ' order(s).' + 
                             (result.failureCount > 0 ? ' (' + result.failureCount + ' order(s) failed)' : '');
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Failed to process mass approval: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Mass Rejects orders: Status -> 'BASO In Progress', Approved_via_Button__c -> false, creates Billing_Approval_Audit__c with Rejection_Reason__c
     */
    public static ActionResultWrapper processMassRejection(List<Id> orderIds, String rejectionReason) {
        ActionResultWrapper result = new ActionResultWrapper();
        result.successCount = 0;
        result.failureCount = 0;
        result.errorDetails = new List<String>();
        result.successfulOrderIds = new List<String>();
        result.failedOrders = new List<FailedOrderDTO>();

        if (orderIds == null || orderIds.isEmpty()) {
            result.isSuccess = false;
            result.message = 'No orders selected to reject.';
            return result;
        }

        if (String.isBlank(rejectionReason)) {
            result.isSuccess = false;
            result.message = 'Rejection reason is required.';
            return result;
        }

        try {
            List<Order> ordersToUpdate = [
                SELECT Id, Status, OrderNumber, Account.Name, Bill_to_Account__r.Name, Service_ID__c, Approved_via_Button__c 
                FROM Order 
                WHERE Id IN :orderIds AND Status = 'Billing Approval'
            ];

            if (ordersToUpdate.isEmpty()) {
                result.isSuccess = false;
                result.message = 'No valid orders found with "Billing Approval" status.';
                return result;
            }

            for (Order ord : ordersToUpdate) {
                ord.Status = 'BASO In Progress';
                ord.Approved_via_Button__c = false;
            }

            Database.SaveResult[] srList = Database.update(ordersToUpdate, false);
            List<Billing_Approval_Audit__c> auditLogs = new List<Billing_Approval_Audit__c>();
            Datetime now = Datetime.now();
            Id currentUserId = UserInfo.getUserId();
            String cleanReason = rejectionReason.trim();

            for (Integer i = 0; i < srList.size(); i++) {
                Database.SaveResult sr = srList[i];
                Order ord = ordersToUpdate[i];

                if (sr.isSuccess()) {
                    result.successCount++;
                    result.successfulOrderIds.add(ord.Id);
                    Billing_Approval_Audit__c audit = new Billing_Approval_Audit__c();
                    audit.Sales_Order__c = ord.Id;
                    audit.Action_Taken__c = 'Rejected';
                    audit.Rejection_Reason__c = cleanReason;
                    audit.Processed_By__c = currentUserId;
                    audit.Action_Date_Time__c = now;
                    auditLogs.add(audit);
                } else {
                    result.failureCount++;
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += (String.isBlank(errMsg) ? '' : '; ') + err.getMessage();
                    }
                    FailedOrderDTO failedDto = new FailedOrderDTO();
                    failedDto.orderId = ord.Id;
                    failedDto.orderNumber = ord.OrderNumber;
                    failedDto.customerAccountName = ord.Account != null ? ord.Account.Name : '-';
                    failedDto.billingAccountName = ord.Bill_to_Account__r != null ? ord.Bill_to_Account__r.Name : '-';
                    failedDto.serviceId = ord.Service_ID__c;
                    failedDto.errorMessage = errMsg;
                    result.failedOrders.add(failedDto);
                    result.errorDetails.add('Order ' + ord.OrderNumber + ': ' + errMsg);
                }
            }

            if (!auditLogs.isEmpty()) {
                Database.insert(auditLogs, false);
            }

            result.isSuccess = (result.successCount > 0);
            result.message = 'Successfully rejected ' + result.successCount + ' order(s).' + 
                             (result.failureCount > 0 ? ' (' + result.failureCount + ' order(s) failed)' : '');
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'Failed to process mass rejection: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Helper to transform Order record into DTO with Business Rules (SO DO logic & CPQ bundle pricing)
     */
    private static OrderReviewDTO mapOrderToDTO(Order ord, String validationStatus, String validationMessage) {
        OrderReviewDTO dto = new OrderReviewDTO();
        dto.id = ord.Id;
        dto.orderId = ord.Id;
        dto.orderNumber = ord.OrderNumber;
        dto.orderType = ord.Type;
        dto.statusOrder = ord.Status;
        dto.customerAccountId = ord.AccountId;
        dto.customerAccountName = ord.Account != null ? ord.Account.Name : '-';
        dto.billingAccountId = ord.Bill_to_Account__c;
        dto.billingAccountName = ord.Bill_to_Account__r != null ? ord.Bill_to_Account__r.Name : '-';
        dto.serviceId = ord.Service_ID__c;
        dto.validationStatus = validationStatus;
        dto.validationMessage = validationMessage;

                // Logic Billing Date:
        // SO DO (Deactive / Disconnect) & SO Suspend -> ambil Billing_End_Date__c
        // Selain itu (New / AO, Modify / MO, Resume / RO) -> ambil Billing_Start_Date__c
        Boolean isEndBilling = (ord.Type != null && (
            ord.Type.equalsIgnoreCase('Deactive') || 
            ord.Type.equalsIgnoreCase('Disconnect') || 
            ord.Type.equalsIgnoreCase('Suspend')
        ));
        dto.billingDate = isEndBilling ? ord.Billing_End_Date__c : ord.Billing_Start_Date__c;

        // Aggregate Product Name & Pricing across ALL OrderItems
        if (ord.OrderItems != null && !ord.OrderItems.isEmpty()) {
            String mainProdName = '';
            Decimal totalListPrice = 0;
            Decimal totalDiscount = 0;
            Decimal calculatedTotal = 0;

            if (ord.OrderItems[0].Product2 != null) {
                mainProdName = ord.OrderItems[0].Product2.Name;
            }

            for (OrderItem oi : ord.OrderItems) {
                Decimal qlp = oi.SBQQ__QuotedListPrice__c != null ? oi.SBQQ__QuotedListPrice__c : 
                             (oi.ListPrice != null ? oi.ListPrice : (oi.UnitPrice != null ? oi.UnitPrice : 0));
                totalListPrice += qlp;

                Decimal disc = oi.Total_Discount_Amt__c != null ? oi.Total_Discount_Amt__c : 0;
                totalDiscount += disc;

                Decimal netTot = oi.Total_Price_Custom__c != null ? oi.Total_Price_Custom__c : 
                                (oi.TotalPrice != null ? oi.TotalPrice : 0);
                calculatedTotal += netTot;
            }

            dto.productName = String.isNotBlank(mainProdName) ? mainProdName : '-';
            dto.quoteListPrice = totalListPrice > 0 ? totalListPrice : (ord.TotalAmount != null ? ord.TotalAmount : 0);
            dto.discount = totalDiscount;
            dto.total = calculatedTotal > 0 ? calculatedTotal : (ord.TotalAmount != null ? ord.TotalAmount : 0);
        } else {
            dto.productName = '-';
            dto.quoteListPrice = ord.TotalAmount != null ? ord.TotalAmount : 0;
            dto.discount = 0;
            dto.total = ord.TotalAmount != null ? ord.TotalAmount : 0;
        }

        return dto;
    }

    /**
     * @description Backward-compatible method if needed
     */
    public static Integer populateReviewData(Id customerAccountId) {
        List<Id> accIds = customerAccountId != null ? new List<Id>{ customerAccountId } : null;
        ResponseWrapper res = getLiveOrders(accIds, null);
        return res != null && res.records != null ? res.records.size() : 0;
    }
}