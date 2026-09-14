import { LightningElement, track, wire } from 'lwc';
import getLiveOrders from '@salesforce/apex/MassBillingApprovalController.getLiveOrders';
import getOrdersByUploadedKeys from '@salesforce/apex/MassBillingApprovalController.getOrdersByUploadedKeys';
import getCustomerAccountOptions from '@salesforce/apex/MassBillingApprovalController.getCustomerAccountOptions';
import executeMassApprove from '@salesforce/apex/MassBillingApprovalController.executeMassApprove';
import executeMassReject from '@salesforce/apex/MassBillingApprovalController.executeMassReject';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import TEMPLATE_CSV from '@salesforce/resourceUrl/MassBillingTemplate';

const LIVE_COLUMNS = [
    { label: 'Order Status', fieldName: 'statusOrder', type: 'text', initialWidth: 140 },
    { 
        label: 'Order Number', 
        fieldName: 'orderUrl', 
        type: 'url', 
        typeAttributes: { 
            label: { fieldName: 'orderNumber' }, 
            target: '_blank' 
        }, 
        initialWidth: 140 
    },
    { label: 'Order Type', fieldName: 'orderType', type: 'text', initialWidth: 110 },
    { 
        label: 'Customer Account', 
        fieldName: 'customerAccountUrl', 
        type: 'url', 
        typeAttributes: { 
            label: { fieldName: 'customerAccountName' }, 
            target: '_blank' 
        }, 
        initialWidth: 220 
    },
    { 
        label: 'Billing Account', 
        fieldName: 'billingAccountUrl', 
        type: 'url', 
        typeAttributes: { 
            label: { fieldName: 'billingAccountName' }, 
            target: '_blank' 
        }, 
        initialWidth: 220 
    },
    { 
        label: 'Billing Date', 
        fieldName: 'billingDate', 
        type: 'date-local',
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' },
        initialWidth: 130 
    },
    { label: 'Product Name', fieldName: 'productName', type: 'text', initialWidth: 200 },
    { 
        label: 'Quote List Price', 
        fieldName: 'quoteListPrice', 
        type: 'currency', 
        typeAttributes: { currencyCode: 'IDR', maximumFractionDigits: 0 },
        initialWidth: 160 
    },
    { 
        label: 'Discount', 
        fieldName: 'discount', 
        type: 'currency', 
        typeAttributes: { currencyCode: 'IDR', maximumFractionDigits: 0 },
        initialWidth: 130 
    },
    { 
        label: 'Total', 
        fieldName: 'total', 
        type: 'currency', 
        typeAttributes: { currencyCode: 'IDR', maximumFractionDigits: 0 },
        initialWidth: 160 
    },
    { label: 'Service ID', fieldName: 'serviceId', type: 'text', initialWidth: 150 }
];

const UPLOAD_COLUMNS = [
    ...LIVE_COLUMNS,
    { label: 'Validation Status', fieldName: 'validationStatus', type: 'text', initialWidth: 140 },
    { label: 'Validation Notes', fieldName: 'validationMessage', type: 'text', initialWidth: 260 }
];

const FAILED_COLUMNS = [
    { 
        label: 'Order Number', 
        fieldName: 'orderUrl', 
        type: 'url', 
        typeAttributes: { 
            label: { fieldName: 'orderNumber' }, 
            target: '_blank' 
        }, 
        initialWidth: 140 
    },
    { label: 'Customer Account', fieldName: 'customerAccountName', type: 'text', initialWidth: 200 },
    { label: 'Billing Account', fieldName: 'billingAccountName', type: 'text', initialWidth: 200 },
    { label: 'Service ID', fieldName: 'serviceId', type: 'text', initialWidth: 130 },
    { label: 'Validation Error Reason', fieldName: 'errorMessage', type: 'text', wrapText: true }
];

export default class MassBillingApproval extends LightningElement {
    @track activeTab = 'liveQuery';
    @track liveRecords = [];
    @track uploadedRecords = [];
    @track allAccountOptions = [];
    @track selectedCustomers = []; // [{ id, name }]
    @track searchKey = '';
    @track isLoading = false;
    @track uploadResultSummary = '';

    // Selection & Mass Action State
    @track selectedRowKeys = [];
    @track selectedRows = [];
    @track isApproveModalOpen = false;
    @track isRejectModalOpen = false;
    @track isErrorModalOpen = false;
    @track failedOrdersData = [];
    @track executionSummaryMessage = '';
    @track rejectionReason = '';
    currentUserId = Id;

    @wire(getCustomerAccountOptions)
    wiredAccountOptions({ error, data }) {
        if (data) {
            this.allAccountOptions = data;
        } else if (error) {
            console.error('Error fetching CA account options:', error);
        }
    }

    connectedCallback() {
        this.fetchLiveOrders();
    }

    get records() {
        return this.activeTab === 'uploadFile' ? this.uploadedRecords : this.liveRecords;
    }

    formatRecords(rawList) {
        if (!rawList) return [];
        return rawList.map(row => {
            const isNF = row.id && String(row.id).startsWith('NF_');
            return {
                ...row,
                orderUrl: (row.orderId && !isNF) ? `/${row.orderId}` : null,
                customerAccountUrl: (row.customerAccountId && row.customerAccountId !== '-') ? `/${row.customerAccountId}` : null,
                billingAccountUrl: (row.billingAccountId && row.billingAccountId !== '-') ? `/${row.billingAccountId}` : null
            };
        });
    }

    fetchLiveOrders() {
        this.isLoading = true;
        this.selectedRowKeys = [];
        this.selectedRows = [];
        const custIds = this.selectedCustomers.map(c => c.id);
        
        getLiveOrders({ customerAccountIds: custIds.length > 0 ? custIds : null, searchKey: null })
            .then(result => {
                if (result.isSuccess) {
                    this.liveRecords = this.formatRecords(result.records || []);
                } else {
                    this.showToast('Attention', result.message, 'warning');
                }
            })
            .catch(error => {
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Failed to load data', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleLiveTabActive() {
        this.activeTab = 'liveQuery';
        this.searchKey = '';
        this.selectedRowKeys = [];
        this.selectedRows = [];
        if (!this.liveRecords || this.liveRecords.length === 0) {
            this.fetchLiveOrders();
        }
    }

    handleUploadTabActive() {
        this.activeTab = 'uploadFile';
        this.searchKey = '';
        this.selectedRowKeys = [];
        this.selectedRows = [];
    }

    get columns() {
        return this.activeTab === 'uploadFile' ? UPLOAD_COLUMNS : LIVE_COLUMNS;
    }

    get availableAccountOptions() {
        if (!this.allAccountOptions) return [];
        const selectedIds = new Set(this.selectedCustomers.map(c => c.id));
        return this.allAccountOptions.filter(opt => !selectedIds.has(opt.value));
    }

    get hasSelectedCustomers() {
        return this.selectedCustomers && this.selectedCustomers.length > 0;
    }

    get selectedCustomerCount() {
        return this.selectedCustomers ? this.selectedCustomers.length : 0;
    }

    get hasData() {
        return !this.isLoading && this.filteredRecords && this.filteredRecords.length > 0;
    }

    get isTableEmpty() {
        return !this.isLoading && (!this.filteredRecords || this.filteredRecords.length === 0);
    }

    get totalRecordsBadge() {
        const count = this.filteredRecords ? this.filteredRecords.length : 0;
        return `${count} Orders`;
    }

    get grandTotalBadge() {
        const sum = this.filteredRecords.reduce((acc, row) => acc + (row.total || 0), 0);
        return 'Total Revenue: ' + new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(sum);
    }

    get emptyTableTitle() {
        if (this.activeTab === 'uploadFile') {
            return 'No file uploaded yet';
        }
        return 'No Orders with Billing Approval Status';
    }

    get emptyTableSubtitle() {
        if (this.activeTab === 'uploadFile') {
            return 'Please select a CSV/Excel file containing a list of Order Numbers or Service IDs to validate.';
        }
        return 'Currently there are no Orders awaiting billing approval (or matching selected filters).';
    }

    get validRecords() {
        if (!this.filteredRecords) return [];
        return this.filteredRecords.filter(r => r.orderId && !String(r.id).startsWith('NF_') && r.statusOrder === 'Billing Approval');
    }

    get validRecordCount() {
        return this.validRecords ? this.validRecords.length : 0;
    }

    get selectAllButtonLabel() {
        return 'Select All';
    }

    get isSelectAllDisabled() {
        return this.validRecordCount === 0 || this.isLoading;
    }

    handleSelectAllValid() {
        const valids = this.validRecords;
        this.selectedRows = valids;
        this.selectedRowKeys = valids.map(r => r.id);
    }

    handleDeselectAll() {
        this.selectedRows = [];
        this.selectedRowKeys = [];
    }

    get selectedRowCount() {
        return this.selectedRows ? this.selectedRows.length : 0;
    }

    get hasSelectedRows() {
        return this.selectedRowCount > 0;
    }

    get selectedCountBadge() {
        return `Selected: ${this.selectedRowCount} Orders`;
    }

    get approveButtonLabel() {
        return `Approve Selected (${this.selectedRowCount})`;
    }

    get rejectButtonLabel() {
        return `Reject Selected (${this.selectedRowCount})`;
    }

    get isActionDisabled() {
        return !this.hasSelectedRows || this.isLoading;
    }

    get isRejectBtnDisabled() {
        return !this.rejectionReason || this.rejectionReason.trim() === '' || this.isLoading;
    }

    get currentUserName() {
        return 'Billing User';
    }

    get filteredRecords() {
        if (!this.records) return [];
        if (!this.searchKey || this.searchKey.trim() === '') {
            return this.records;
        }
        const sk = this.searchKey.toLowerCase();
        return this.records.filter(r => 
            (r.orderNumber && r.orderNumber.toLowerCase().includes(sk)) ||
            (r.customerAccountName && r.customerAccountName.toLowerCase().includes(sk)) ||
            (r.billingAccountName && r.billingAccountName.toLowerCase().includes(sk)) ||
            (r.productName && r.productName.toLowerCase().includes(sk)) ||
            (r.serviceId && r.serviceId.toLowerCase().includes(sk)) ||
            (r.statusOrder && r.statusOrder.toLowerCase().includes(sk))
        );
    }

    handleRowSelection(event) {
        const selected = event.detail.selectedRows || [];
        // Filter only valid orders (must have valid Salesforce Order Id and status == 'Billing Approval')
        const validSelected = selected.filter(r => r.orderId && !r.id.startsWith('NF_') && r.statusOrder === 'Billing Approval');
        this.selectedRows = validSelected;
        this.selectedRowKeys = validSelected.map(r => r.id);
    }

    handleOpenApproveModal() {
        if (this.selectedRows.length === 0) {
            this.showToast('Attention', 'Please select at least 1 order to approve.', 'warning');
            return;
        }
        this.isApproveModalOpen = true;
    }

    handleCloseApproveModal() {
        this.isApproveModalOpen = false;
    }

    get failedColumns() {
        return FAILED_COLUMNS;
    }

    get failedOrdersCount() {
        return this.failedOrdersData ? this.failedOrdersData.length : 0;
    }

    handleCloseErrorModal() {
        this.isErrorModalOpen = false;
        this.failedOrdersData = [];
        this.executionSummaryMessage = '';
    }

    formatFailedOrders(rawList) {
        if (!rawList) return [];
        return rawList.map(item => ({
            ...item,
            orderUrl: item.orderId ? `/${item.orderId}` : null
        }));
    }

    handleDownloadFailedCsv() {
        if (!this.failedOrdersData || this.failedOrdersData.length === 0) return;
        let csv = 'Order Number,Customer Account,Billing Account,Service ID,Validation Error Reason\r\n';
        this.failedOrdersData.forEach(row => {
            const line = [
                this.escapeCsv(row.orderNumber),
                this.escapeCsv(row.customerAccountName),
                this.escapeCsv(row.billingAccountName),
                this.escapeCsv(row.serviceId),
                this.escapeCsv(row.errorMessage)
            ].join(',');
            csv += line + '\r\n';
        });
        const today = new Date().toISOString().slice(0, 10);
        this.downloadCsvFile(csv, `Failed_Orders_${today}.csv`);
    }

    handleConfirmApprove() {
        const orderIds = this.selectedRows.map(r => r.orderId);
        this.isLoading = true;
        this.isApproveModalOpen = false;

        executeMassApprove({ orderIds })
            .then(result => {
                const successIds = new Set(result.successfulOrderIds || []);
                const failedList = result.failedOrders || [];

                if (result.isSuccess) {
                    if (result.failureCount > 0) {
                        this.executionSummaryMessage = `Successfully approved ${result.successCount} order(s), but ${result.failureCount} order(s) failed validation.`;
                        this.failedOrdersData = this.formatFailedOrders(failedList);
                        this.isErrorModalOpen = true;
                        this.showToast('Partial Approval Completed', this.executionSummaryMessage, 'warning');
                    } else {
                        this.showToast('Approval Success', result.message, 'success');
                    }

                    this.selectedRowKeys = [];
                    this.selectedRows = [];

                    if (this.activeTab === 'liveQuery') {
                        this.fetchLiveOrders();
                    } else {
                        const errorMap = new Map(failedList.map(f => [f.orderId, f.errorMessage]));
                        this.uploadedRecords = this.uploadedRecords.map(r => {
                            if (successIds.has(r.orderId)) {
                                return { ...r, statusOrder: 'Completed', validationStatus: 'Processed', validationMessage: 'Successfully approved' };
                            } else if (errorMap.has(r.orderId)) {
                                return { ...r, validationStatus: 'Failed', validationMessage: errorMap.get(r.orderId) };
                            }
                            return r;
                        });
                    }
                } else {
                    if (failedList.length > 0) {
                        this.executionSummaryMessage = `Approval failed for all ${result.failureCount} selected order(s).`;
                        this.failedOrdersData = this.formatFailedOrders(failedList);
                        this.isErrorModalOpen = true;
                    }
                    const errDetail = (result.errorDetails && result.errorDetails.length > 0) ? ': ' + result.errorDetails.slice(0, 2).join(', ') : '';
                    this.showToast('Approval Failed', result.message + errDetail, 'error');
                }
            })
            .catch(error => {
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Approval Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleOpenRejectModal() {
        if (this.selectedRows.length === 0) {
            this.showToast('Attention', 'Please select at least 1 order to reject.', 'warning');
            return;
        }
        this.rejectionReason = '';
        this.isRejectModalOpen = true;
    }

    handleCloseRejectModal() {
        this.isRejectModalOpen = false;
        this.rejectionReason = '';
    }

    handleRejectionReasonChange(event) {
        this.rejectionReason = event.target.value;
    }

    handleConfirmReject() {
        if (!this.rejectionReason || this.rejectionReason.trim() === '') {
            this.showToast('Warning', 'Rejection reason is required.', 'warning');
            return;
        }

        const orderIds = this.selectedRows.map(r => r.orderId);
        this.isLoading = true;
        this.isRejectModalOpen = false;

        executeMassReject({ orderIds, rejectionReason: this.rejectionReason })
            .then(result => {
                const successIds = new Set(result.successfulOrderIds || []);
                const failedList = result.failedOrders || [];

                if (result.isSuccess) {
                    if (result.failureCount > 0) {
                        this.executionSummaryMessage = `Successfully rejected ${result.successCount} order(s), but ${result.failureCount} order(s) failed.`;
                        this.failedOrdersData = this.formatFailedOrders(failedList);
                        this.isErrorModalOpen = true;
                        this.showToast('Partial Rejection Completed', this.executionSummaryMessage, 'warning');
                    } else {
                        this.showToast('Reject Success', result.message, 'success');
                    }

                    this.selectedRowKeys = [];
                    this.selectedRows = [];
                    this.rejectionReason = '';

                    if (this.activeTab === 'liveQuery') {
                        this.fetchLiveOrders();
                    } else {
                        const errorMap = new Map(failedList.map(f => [f.orderId, f.errorMessage]));
                        this.uploadedRecords = this.uploadedRecords.map(r => {
                            if (successIds.has(r.orderId)) {
                                return { ...r, statusOrder: 'BASO In Progress', validationStatus: 'Rejected', validationMessage: 'Successfully rejected' };
                            } else if (errorMap.has(r.orderId)) {
                                return { ...r, validationStatus: 'Failed', validationMessage: errorMap.get(r.orderId) };
                            }
                            return r;
                        });
                    }
                } else {
                    if (failedList.length > 0) {
                        this.executionSummaryMessage = `Rejection failed for all ${result.failureCount} selected order(s).`;
                        this.failedOrdersData = this.formatFailedOrders(failedList);
                        this.isErrorModalOpen = true;
                    }
                    const errDetail = (result.errorDetails && result.errorDetails.length > 0) ? ': ' + result.errorDetails.slice(0, 2).join(', ') : '';
                    this.showToast('Reject Failed', result.message + errDetail, 'error');
                }
            })
            .catch(error => {
                const msg = error.body ? error.body.message : error.message;
                this.showToast('Reject Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleAddCustomerAccount(event) {
        const accId = event.detail.value;
        if (!accId) return;

        const found = this.allAccountOptions.find(o => o.value === accId);
        if (found && !this.selectedCustomers.some(c => c.id === accId)) {
            this.selectedCustomers = [...this.selectedCustomers, { id: found.value, name: found.label }];
            this.fetchLiveOrders();
        }
        event.target.value = '';
    }

    handleRemoveCustomer(event) {
        const accId = event.currentTarget.dataset.id;
        this.selectedCustomers = this.selectedCustomers.filter(c => c.id !== accId);
        this.fetchLiveOrders();
    }

    handleClearAllCustomers() {
        this.selectedCustomers = [];
        this.fetchLiveOrders();
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
    }

    handleRefreshData() {
        this.fetchLiveOrders();
    }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.isLoading = true;
        this.selectedRowKeys = [];
        this.selectedRows = [];
        const reader = new FileReader();

        reader.onload = () => {
            const text = reader.result;
            const keys = this.parseCsvKeys(text);

            if (keys.length === 0) {
                this.isLoading = false;
                this.showToast('Failed', 'File does not contain readable Order Number / SID data.', 'error');
                return;
            }

            getOrdersByUploadedKeys({ orderNumbersOrSids: keys })
                .then(result => {
                    if (result.isSuccess) {
                        this.uploadedRecords = this.formatRecords(result.records || []);
                        this.uploadResultSummary = result.message;
                        // Auto-select all valid orders so user can approve in 1 click
                        const validUploaded = this.uploadedRecords.filter(r => r.orderId && !String(r.id).startsWith('NF_') && r.statusOrder === 'Billing Approval');
                        this.selectedRows = validUploaded;
                        this.selectedRowKeys = validUploaded.map(r => r.id);
                        this.showToast('Upload Success', result.message, 'success');
                    } else {
                        this.showToast('Attention', result.message, 'warning');
                    }
                })
                .catch(error => {
                    const msg = error.body ? error.body.message : error.message;
                    this.showToast('Failed to Process File', msg, 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        };

        reader.onerror = () => {
            this.isLoading = false;
            this.showToast('Error', 'Failed to read file from computer.', 'error');
        };

        reader.readAsText(file);
    }

    parseCsvKeys(csvText) {
        if (!csvText) return [];
        const lines = csvText.split(/\r\n|\n|\r/);
        const keys = [];
        let targetColIndex = 0;
        let startRowIndex = 0;

        // Check if first line is a header
        if (lines.length > 0 && lines[0].trim()) {
            const headerParts = lines[0].split(/[,;\t]/).map(p => p.replace(/^["']|["']$/g, '').trim().toLowerCase());
            const foundIdx = headerParts.findIndex(h => 
                h.includes('order') || h.includes('nomor') || h.includes('sid') || h.includes('service')
            );
            if (foundIdx !== -1) {
                targetColIndex = foundIdx;
                startRowIndex = 1; // Skip header row
            }
        }

        for (let i = startRowIndex; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            const parts = line.split(/[,;\t]/);
            let val = '';
            if (parts.length > targetColIndex) {
                val = parts[targetColIndex].replace(/^["']|["']$/g, '').trim();
            } else if (parts.length > 0) {
                val = parts[0].replace(/^["']|["']$/g, '').trim();
            }

            if (val) {
                // Auto-pad leading zero if numeric and less than 8 digits (Excel stripping fix)
                if (/^\d+$/.test(val) && val.length < 8) {
                    val = val.padStart(8, '0');
                }
                keys.push(val);
            }
        }

        return keys;
    }

    get templateUrl() {
        return TEMPLATE_CSV;
    }

    downloadCsvFile(csvContent, fileName) {
        try {
            const encodedUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvContent);
            const downloadLink = this.template.querySelector('.hidden-csv-download');
            if (downloadLink) {
                downloadLink.href = encodedUri;
                downloadLink.download = fileName;
                downloadLink.click();
            } else {
                const link = document.createElement('a');
                link.setAttribute('href', encodedUri);
                link.setAttribute('download', fileName);
                link.setAttribute('target', '_self');
                document.body.appendChild(link);
                link.click();
                setTimeout(() => {
                    try {
                        document.body.removeChild(link);
                    } catch (e) {
                        // Ignore cleanup error
                    }
                }, 200);
            }
        } catch (err) {
            console.error('Error downloading CSV:', err);
            this.showToast('Download Error', 'Could not initiate file download: ' + err.message, 'error');
        }
    }

    handleDownloadTemplate() {
        if (TEMPLATE_CSV) {
            window.open(TEMPLATE_CSV, '_blank');
        }
    }

    handleExportData() {
        if (!this.filteredRecords || this.filteredRecords.length === 0) {
            this.showToast('Info', 'No data to export', 'info');
            return;
        }

        let csv = 'Order Status,Order Number,Order Type,Customer Account,Billing Account,Billing Date,Product Name,Quote List Price,Discount,Total,Service ID\r\n';
        this.filteredRecords.forEach(row => {
            const line = [
                this.escapeCsv(row.statusOrder),
                this.escapeCsv(row.orderNumber),
                this.escapeCsv(row.orderType),
                this.escapeCsv(row.customerAccountName),
                this.escapeCsv(row.billingAccountName),
                this.escapeCsv(row.billingDate),
                this.escapeCsv(row.productName),
                row.quoteListPrice || 0,
                row.discount || 0,
                row.total || 0,
                this.escapeCsv(row.serviceId)
            ].join(',');
            csv += line + '\r\n';
        });

        const today = new Date().toISOString().slice(0, 10);
        this.downloadCsvFile(csv, `Mass_Billing_Review_${today}.csv`);
    }

    escapeCsv(val) {
        if (!val) return '""';
        return `"${String(val).replace(/"/g, '""')}"`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}