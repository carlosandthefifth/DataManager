/*
===========================================================================================================================================
|    Programmer: Daniel Gustafson                                                                                                         |
|                                                                                                                                         |
|    Version 1.0                                                                                                                          |
|                                                                                                                                         | 
|    Date: November 7, 2019                                                                                                               |  
|                                                                                                                                         |
|   Purpose:                                                                                                                              |  
|    Provides a solution to mass update large record sets (greater 10000) declaratively                                                   |  
|                                                                                                                                         |  
|    -------------------------------------------------------------------------------------------------------------------------------      |
|    |Version| Contributor            |Date      |Description/Reason                                                                      |  
|    ------------------------------------------------------------------------------------------------------------------------------       |
|    |       |                        |          |                                                                                        |  
|    |       |                        |          |                                                                                        |  
|    -------------------------------------------------------------------------------------------------------------------------------------|
|==========================================================================================================================================    
*/
public without sharing class DataManagerClass {

    public class DataManagerClassException extends Exception {}

    public static boolean ThrowException_CodeCoverage = false;

    // TIME 
    private static integer ONE_SECOND = 1;
    // LIMITS SECTION
    public static integer  QueriesPerTransaction_LIMIT     = Limits.getLimitQueryRows(); // getQueryRows() 
    public static integer  FuturePerTransaction_LIMIT      = Limits.getLimitFutureCalls(); //getFutureCalls()
    public static integer  EmailPerTransaction_LIMIT       = Limits.getLimitEmailInvocations(); // getEmailInvocations()
    public static integer  DMLPerTransaction_LIMIT         = Limits.getLimitDmlRows(); // getDMLStatements()
    public static integer  RowsPerTransaction_LIMIT        = Limits.getLimitQueryRows(); // getQueryRows()
    
    private static integer DATA_BATCH_SIZE                 = DMLPerTransaction_LIMIT;

    // Primary variables
    private static List<Data_Manager__mdt> DataManagerList = new List<Data_Manager__mdt>();
    private static Map<Integer, List<ID>> IDsToProcess = new Map<Integer, List<ID>>();
    private static Map<Integer,Integer> RecordsToInsert = new Map<Integer,Integer>();
    private static List<ID> IDsMarked = new List<ID>();
    private static List<SObject> objects = new List<SObject>();
    private static List<String> Parameters = new List<String>();

    public DataManagerClass() {
        // Set limit values
        QueriesPerTransaction_LIMIT     = Limits.getLimitQueryRows(); // getQueryRows() 
        FuturePerTransaction_LIMIT      = Limits.getLimitFutureCalls(); //getFutureCalls()
        EmailPerTransaction_LIMIT       = Limits.getLimitEmailInvocations(); // getEmailInvocations()
        DMLPerTransaction_LIMIT         = Limits.getLimitDmlRows(); // getDMLStatements()
        RowsPerTransaction_LIMIT        = Limits.getLimitQueryRows(); // getQueryRows()
    }

    public static void execute () {
        String empty = '';
        execute (empty); 
    } 

    public static void execute (String ProjectName) 
    { 
        String ComparativeOperator = '';
        String query               = '';
        Integer TotalRecords       = 0;
        Integer BatchIndex         = 0;
        Integer RecordIndex        = 0; 
        List<ID> BatchIds          = new List<ID>();
        Integer LastCount          = 0;

        system.debug('inside execute');

        if (ProjectName == '') {
            // Running all available projects
            query = 'SELECT Verb__c, Compare_Value_Is_Blank__c, Record_Count__c, Label, Object_API_Name__c, New_Value_Is_Blank__c, New_Value__c, Use_Criteria__c, Compare_Value__c, Comparative_Operator__c, Compare_API_Field_Name__c, API_Field_Name__c, Add_Suffix_Iterator__c, Active__c, Use_Query__c, Email_Recipient__c, Email_Notification__c FROM Data_Manager__mdt WHERE Active__c = true LIMIT ' + DMLPerTransaction_LIMIT;
        }
        else {
            // Select a specific project to run
            query = 'SELECT Verb__c, Compare_Value_Is_Blank__c, Record_Count__c, Label, Object_API_Name__c, New_Value_Is_Blank__c, New_Value__c, Use_Criteria__c, Compare_Value__c, Comparative_Operator__c, Compare_API_Field_Name__c, API_Field_Name__c, Add_Suffix_Iterator__c, Active__c, Use_Query__c, Email_Recipient__c, Email_Notification__c FROM Data_Manager__mdt WHERE Active__c = true  AND Label =:ProjectName LIMIT ' + DMLPerTransaction_LIMIT;
        }
        try {
            DataManagerList = database.query(query);
            
            for (Data_Manager__mdt DataManager : DataManagerList) {
                // Build query for total records
                Parameters.add(DataManager.Object_API_Name__c);
                if(DataManager.Verb__c == 'Update') {
                    if((DataManager.Use_Criteria__c) && !(DataManager.Use_Query__c)) {
                        query = 'SELECT ID FROM {0} WHERE {1} {2} {3} LIMIT {4}';
                        // Get the operator
                        if (DataManager.Comparative_Operator__c == 'Equal')
                            ComparativeOperator = '=';
                        if (DataManager.Comparative_Operator__c == 'Less Than')
                            ComparativeOperator = '<';
                        if (DataManager.Comparative_Operator__c == 'Less Than Equal To')
                            ComparativeOperator = '<=';
                        if (DataManager.Comparative_Operator__c == 'Greater Than')
                            ComparativeOperator = '>';
                        if (DataManager.Comparative_Operator__c == 'Greater Than Equal To')
                            ComparativeOperator = '>=';
                        if (DataManager.Comparative_Operator__c == 'Not Equal')
                            ComparativeOperator = '!=';
                        
                        Parameters.add(DataManager.Compare_API_Field_Name__c);
                        Parameters.add(ComparativeOperator);    
                        if (DataManager.Compare_Value_Is_Blank__c)
                            Parameters.add(' \' \' ');
                        else
                            Parameters.add(DataManager.Compare_Value__c);
                    }  else {
                        if (DataManager.Use_Query__c)
                            query = DataManager.query__c;
                        else 
                            query = 'SELECT ID FROM {0} LIMIT {1}';
                    }

                    if (!DataManager.Use_Query__c) {
                        Parameters.add(string.valueOf(RowsPerTransaction_LIMIT - LIMITS.getQueryRows()));

                        query = string.format(query,Parameters);
                    }

                    system.debug('query: ' + query);

                    try {
                        objects = database.query(query);
                    } catch (Exception e) {
                        system.debug('on update query error: ' + e.getMessage());
                    }

                    TotalRecords = objects.size();
                    system.debug('-- TotalRecords: ' + TotalRecords);
                    BatchIndex = 0;
                    for (SObject obj : objects) {
                        BatchIds.add(obj.id);
                        RecordIndex++;
                    if (RecordIndex > DMLPerTransaction_LIMIT - 1) {
                            RecordIndex = 0;
                            IDsToProcess.put(BatchIndex, BatchIds);
                            BatchIndex++;
                            BatchIds = New List<Id>();
                        }
                        
                    }
                    
                    if (BatchIds.size() > 0 ) {
                        IDsToProcess.put(BatchIndex,BatchIds);
                    }

                } else { 
                    TotalRecords = (Integer)DataManager.Record_Count__c;

                    // Break records up into DML Batches
                    BatchIndex = 0;
                    while (TotalRecords >= DMLPerTransaction_LIMIT) {
                        if (TotalRecords > DMLPerTransaction_LIMIT) {
                            RecordsToInsert.put(BatchIndex, DMLPerTransaction_LIMIT);
                        }
                        else {
                            RecordsToInsert.put(BatchIndex, TotalRecords);
                        }
                        TotalRecords -= DMLPerTransaction_LIMIT;
                        BatchIndex++;
                    }
                    if (TotalRecords > 0) RecordsToInsert.put(BatchIndex, TotalRecords);
                    
                }

                system.debug('TotalRecords: ' + TotalRecords);

                LastCount = 0;
                for(Integer BatchKey : RecordsToInsert.keySet()) {
                    system.debug('RecordsToInsert.get(BatchKey): ' + RecordsToInsert.get(BatchKey));
                        InsertRecords(DataManager.Object_API_Name__c, DataManager.API_Field_Name__c, DataManager.New_Value__c, DataManager.Add_Suffix_Iterator__c,RecordsToInsert.get(BatchKey) , LastCount, DataManager.Email_Notification__c, DataManager.Email_Recipient__c);
                        LastCount += RecordsToInsert.get(BatchKey);
                        if (LIMITS.getFutureCalls() + 1 > FuturePerTransaction_LIMIT) break; // we have reached the maximum number of future calls
                }

                for (Integer BatchKey : IDsToProcess.keySet()) {
                    system.debug('IDsToProcess.get(' + BatchKey + ').size(): ' + IDsToProcess.get(BatchKey).size());
                    UpdateRecords(DataManager.Object_API_Name__c, DataManager.API_Field_Name__c, DataManager.New_Value__c, IDsToProcess.get(BatchKey), DataManager.Add_Suffix_Iterator__c,IDsToProcess.get(BatchKey).Size(), LastCount, DataManager.Compare_Value__c,DataManager.Compare_API_Field_Name__c, DataManager.Compare_Value_Is_Blank__c, DataManager.New_Value_Is_Blank__c, DataManager.Email_Notification__c, DataManager.Email_Recipient__c);
                    LastCount += IDsToProcess.get(BatchKey).Size();
                }            
            }
        } catch (Exception e) {
            system.debug('initial setup: ' + e.getMessage());
        }
    }

     
    @future 
    private static void InsertRecords(String APIObjectName, String APIFieldName, String APIFieldValue, Boolean Iterator, Integer RecordCount, Integer LastCount, Boolean Notify, String RecipientEamil)
    {
        List<SObject> objects = new List<SObject>();
        List<ID> ParentIDs = new List<ID>();
        Integer ParentRecordCount = 0;
        String ParentObject = '';
        String query = '';

        // Do we have parent records
        if (APIFieldValue != null) {
            if (APIFieldValue.indexOf('@')==0) {
                ParentObject = APIFieldValue.Replace('@','');
                query = 'SELECT ID FROM ' + ParentObject + ' LIMIT ' + DMLPerTransaction_LIMIT;
                objects = database.query(query);
                for (SObject obj : objects) {
                    ParentIDs.Add(obj.id);
                }            
                objects = new List<SObject>();
            }
        }
        try {
            for (Integer i = 0; i < RecordCount; i ++) {
                SObject obj =  (SObject)Type.forName(APIObjectName).newInstance();
                if (APIFieldName != null) {
                    if (ParentObject == '') {
                        // No parent record
                        if (Iterator) {
                            obj.put(APIFieldName, APIFieldValue + (i + LastCount));
                        }
                        else {
                            obj.put(APIFieldName, APIFieldValue);
                        }
                    } else {
                        // Parent record
                        obj.put(APIFieldName, ParentIds[ParentRecordCount]);
                        ParentRecordCount++;
                        if (ParentRecordCount >= ParentIDs.Size()) ParentRecordCount = 0;
                    }
                }
                objects.add(obj);
            }
            insert objects;
        } catch (Exception e) {
            System.debug('Error Insert Records ' + e.getMessage());
        }

        // email notification section
        // Email notification
        if (Notify) {
            try{

                Messaging.reserveSingleEmailCapacity(1);

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                String[] toAddresses = new String[] {RecipientEamil}; 

                mail.setToAddresses(toAddresses);

                mail.setReplyTo('DataManagerNoReply@MarcusMillichap.com');

 
                mail.setSenderDisplayName('Data Manager');

                mail.setSubject('Data Manager Batch Report');

                // Set to True if you want to BCC yourself on the email.
                mail.setBccSender(false);

                mail.setUseSignature(false);

                // Specify the text content of the email.
                mail.setPlainTextBody(RecordCount + ' record(s) were inserted for object ' + APIObjectName);

                // Send the email you have created.
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            } catch (Exception e) {
                system.debug('Send email fail: ' + e.getMessage());
            }
        }
    }

    @future 
    private static void UpdateRecords(String APIObjectName, String APIFieldName, String APIFieldValue, List<ID> IDsToProcess, boolean Iterator,Integer RecordCount, Integer LastCount, String Compare_Value, String Compare_API_Field_Name, Boolean Value_Is_Blank, Boolean New_Value_Is_Blank, Boolean Notify, String RecipientEamil)
    {
        Boolean CanUpdate = true;
        List<ID> ParentIDs = new List<ID>();
        Integer ParentRecordCount = 0;
        String ParentObject = '';
        String query = '';

        system.debug('inside updaterecords');
        if (APIFieldValue.indexOf('@')==0) {
            ParentObject = APIFieldValue.Replace('@','');
            query = 'SELECT ID FROM ' + ParentObject + ' LIMIT ' + DMLPerTransaction_LIMIT;
            objects = database.query(query);
            for (SObject obj : objects) {
                ParentIDs.Add(obj.id);
            }            
        }

        system.debug('ParentIDs.Size(): ' + ParentIDs.size());
        query = 'SELECT ID, ' + APIFieldName + ' FROM ' + APIObjectName + ' WHERE ID IN :IDsToProcess LIMIT ' + DMLPerTransaction_LIMIT;
        system.debug('Update Records query: ' + query);
        List<SObject> objects = database.query(query);

        for (SObject obj : objects) {
            try {
                if (ParentIds.size() > 0 ){
                    obj.put(APIFieldName,ParentIDs[ParentRecordCount]);
                    ParentRecordCount++;
                    if (ParentRecordCount > ParentIDs.size() - 1)
                        ParentRecordCount = 0;
                }
                else  {
                    obj.put(APIFieldName,APIFieldValue);
                }
            } catch (Exception e) {
                system.debug('UpdateRecords ' + e.getMessage());
            }
        }
        try {
            Update objects;
        } catch (Exception e) {
            system.debug('Update Objects - UpdateRecords: ' + e.getMessage());
        }

        // Email notification
        if (Notify) {
            try{
                Messaging.reserveSingleEmailCapacity(1);

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

                String[] toAddresses = new String[] {RecipientEamil}; 

                mail.setToAddresses(toAddresses);

                mail.setReplyTo('DataManagerNoReply@MarcusMillichap.com');

                mail.setSenderDisplayName('Data Manager');

                mail.setSubject('Data Manager Batch Report');

                // Set to True if you want to BCC yourself on the email.
                mail.setBccSender(false);

                mail.setUseSignature(false);

                // Specify the text content of the email.
                mail.setPlainTextBody(RecordCount + ' record(s) were updated for object ' + APIObjectName);

                // Send the email you have created.
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            } catch (Exception e) {
                system.debug('Send email fail: ' + e.getMessage());
            }
        }
    }
}