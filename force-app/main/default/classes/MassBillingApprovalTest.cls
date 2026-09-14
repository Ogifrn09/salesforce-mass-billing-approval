@IsTest
private class MassBillingApprovalTest {

    @TestSetup
    static void setupData() {
        Id caRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('CA') ? 
                    Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('CA').getRecordTypeId() : null;
        Id baRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('BA') ? 
                    Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('BA').getRecordTypeId() : null;

        Account custAcc = new Account(
            Name = 'PT Test Customer', 
            Account_Type__c = 'CA',
            RecordTypeId = caRtId
        );
        insert custAcc;

        Account billAcc = new Account(
            Name = 'PT Test Billing', 
            Account_Type__c = 'BA',
            ParentId = custAcc.Id,
            RecordTypeId = baRtId
        );
        insert billAcc;

        Product2 prod = new Product2(Name = 'IP Transit 100 Mbps', IsActive = true);
        insert prod;

        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 5000000,
            IsActive = true
        );
        insert pbe;

        // Create Order 1: New (Billing Start Date)
        Order ord1 = new Order(
            AccountId = custAcc.Id,
            Bill_to_Account__c = billAcc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'New',
            Billing_Start_Date__c = Date.today().addDays(5),
            Pricebook2Id = pricebookId,
            Service_ID__c = 'SID-TEST-001'
        );
        insert ord1;

        OrderItem oi1 = new OrderItem(
            OrderId = ord1.Id,
            PricebookEntryId = pbe.Id,
            UnitPrice = 5000000,
            Quantity = 1,
            SBQQ__QuotedListPrice__c = 5000000,
            Unit_Discount_Amt__c = 500000
        );
        insert oi1;

        // Set status to Billing Approval
        ord1.Status = 'Billing Approval';
        update ord1;

        // Create Order 2: Deactive (Billing End Date)
        Order ord2 = new Order(
            AccountId = custAcc.Id,
            Bill_to_Account__c = billAcc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Type = 'Deactive',
            Billing_End_Date__c = Date.today().addDays(-2),
            Pricebook2Id = pricebookId,
            Service_ID__c = 'SID-TEST-002'
        );
        insert ord2;

        OrderItem oi2 = new OrderItem(
            OrderId = ord2.Id,
            PricebookEntryId = pbe.Id,
            UnitPrice = 2000000,
            Quantity = 1,
            SBQQ__QuotedListPrice__c = 2000000,
            Unit_Discount_Amt__c = 0
        );
        insert oi2;

        ord2.Status = 'Billing Approval';
        update ord2;
    }

    @IsTest
    static void testGetLiveOrders() {
        Account cust = [SELECT Id FROM Account WHERE Name = 'PT Test Customer' LIMIT 1];

        Test.startTest();
        // Test All
        MassBillingApprovalService.ResponseWrapper allRes = MassBillingApprovalController.getLiveOrders(null, null);
        // Test Multi-Customer Filter
        MassBillingApprovalService.ResponseWrapper filterRes = MassBillingApprovalController.getLiveOrders(new List<Id>{ cust.Id }, 'SID-TEST');
        Test.stopTest();

        System.assert(allRes.isSuccess, 'Expected live query to succeed');
        System.assert(allRes.records.size() >= 2, 'Expected at least 2 live orders');
        System.assert(filterRes.isSuccess, 'Expected filtered live query to succeed');
        System.assert(!filterRes.records.isEmpty(), 'Expected filtered results');
    }

    @IsTest
    static void testGetOrdersByUploadedKeys() {
        Order ord1 = [SELECT Id, OrderNumber, Service_ID__c FROM Order WHERE Type = 'New' LIMIT 1];
        Order ord2 = [SELECT Id, OrderNumber, Service_ID__c FROM Order WHERE Type = 'Deactive' LIMIT 1];

        // Change ord2 status to Draft (to test invalid status detection)
        ord2.Status = 'Draft';
        update ord2;

        // Test with stripped leading zero (e.g. '68134' instead of '00068134')
        String strippedOrd1 = ord1.OrderNumber.isNumeric() ? String.valueOf(Long.valueOf(ord1.OrderNumber)) : ord1.OrderNumber;
        List<String> uploadList = new List<String>{
            strippedOrd1,
            ord2.OrderNumber,
            'NON_EXISTING_ORDER_999'
        };

        Test.startTest();
        MassBillingApprovalService.ResponseWrapper res = MassBillingApprovalController.getOrdersByUploadedKeys(uploadList);
        Test.stopTest();

        System.assert(res.isSuccess, 'Expected upload processing to succeed');
        System.assertEquals(1, res.validCount, 'Expected 1 valid order in Billing Approval');
        System.assertEquals(2, res.invalidCount, 'Expected 2 invalid/not found orders');
    }

    @IsTest
    static void testGetCustomerAccountOptions() {
        Test.startTest();
        List<Map<String, String>> opts = MassBillingApprovalController.getCustomerAccountOptions();
        Test.stopTest();
        System.assert(!opts.isEmpty(), 'Account options should not be empty');
    }

    @IsTest
    static void testExecuteMassApprove() {
        Order ord1 = [SELECT Id FROM Order WHERE Type = 'New' LIMIT 1];

        Test.startTest();
        MassBillingApprovalService.ActionResultWrapper res = MassBillingApprovalController.executeMassApprove(new List<Id>{ ord1.Id });
        Test.stopTest();

        System.assert(res.isSuccess, 'Mass approve should be successful');
        System.assertEquals(1, res.successCount, 'Should have 1 successful approval');
        System.assertNotEquals(null, res.successfulOrderIds, 'successfulOrderIds should not be null');
        System.assertEquals(1, res.successfulOrderIds.size(), 'successfulOrderIds should have 1 item');

        Order updatedOrd = [SELECT Id, Status, Approved_via_Button__c FROM Order WHERE Id = :ord1.Id];
        System.assertEquals('Completed', updatedOrd.Status, 'Order status should be Completed');
        System.assertEquals(true, updatedOrd.Approved_via_Button__c, 'Approved_via_Button__c should be true');

        List<Billing_Approval_Audit__c> audits = [SELECT Id, Action_Taken__c, Sales_Order__c FROM Billing_Approval_Audit__c WHERE Sales_Order__c = :ord1.Id];
        System.assertEquals(1, audits.size(), 'Audit log record should be created');
        System.assertEquals('Approved', audits[0].Action_Taken__c, 'Action taken should be Approved');
    }

    @IsTest
    static void testExecuteMassReject() {
        Order ord2 = [SELECT Id FROM Order WHERE Type = 'Deactive' LIMIT 1];

        Test.startTest();
        // Test blank rejection reason validation
        MassBillingApprovalService.ActionResultWrapper failRes = MassBillingApprovalController.executeMassReject(new List<Id>{ ord2.Id }, '   ');
        System.assert(!failRes.isSuccess, 'Should fail when rejection reason is blank');

        // Test valid rejection
        MassBillingApprovalService.ActionResultWrapper successRes = MassBillingApprovalController.executeMassReject(new List<Id>{ ord2.Id }, 'Test rejection reason');
        Test.stopTest();

        System.assert(successRes.isSuccess, 'Mass reject should be successful');
        System.assertEquals(1, successRes.successCount, 'Should have 1 successful rejection');

        Order updatedOrd = [SELECT Id, Status, Approved_via_Button__c FROM Order WHERE Id = :ord2.Id];
        System.assertEquals('BASO In Progress', updatedOrd.Status, 'Order status should be BASO In Progress');
        System.assertEquals(false, updatedOrd.Approved_via_Button__c, 'Approved_via_Button__c should be false');

        List<Billing_Approval_Audit__c> audits = [SELECT Id, Action_Taken__c, Rejection_Reason__c FROM Billing_Approval_Audit__c WHERE Sales_Order__c = :ord2.Id];
        System.assertEquals(1, audits.size(), 'Audit log record should be created');
        System.assertEquals('Rejected', audits[0].Action_Taken__c, 'Action taken should be Rejected');
        System.assertEquals('Test rejection reason', audits[0].Rejection_Reason__c, 'Rejection reason should match');
    }

    @IsTest
    static void testLegacyBackwardCompatibility() {
        Account cust = [SELECT Id FROM Account WHERE Name = 'PT Test Customer' LIMIT 1];

        Test.startTest();
        MassBillingApprovalController.ReviewResultWrapper legacyRes = MassBillingApprovalController.populateAndGetOrders(cust.Id);
        List<MassBillingApprovalService.OrderReviewDTO> reviews = MassBillingApprovalController.getReviewRecords(cust.Id, null);
        Test.stopTest();

        System.assert(legacyRes.isSuccess, 'Expected legacy method to succeed');
    }
}