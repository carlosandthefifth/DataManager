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
|    -------------------------------------------------------------------------------------------------------------------------------------|
|    |Version| Contributor            |Date      |Description/Reason                                                                      |  
|    -------------------------------------------------------------------------------------------------------------------------------------|
|    |       |                        |          |                                                                                        |  
|    |       |                        |          |                                                                                        |  
|    -------------------------------------------------------------------------------------------------------------------------------------|
|==========================================================================================================================================    
*/
public without sharing class MassRecordUpdaterClass {

    
    public class MassRecordUpdaterClassException extends Exception {}

    public static boolean ThrowException_CodeCoverage = false;

    // LIMITS SECTION
    public static integer  QueriesPerTransaction_LIMIT     = Limits.getLimitQueryRows(); // getQueryRows() 
    public static integer  FuturePerTransaction_LIMIT      = Limits.getLimitFutureCalls(); //getFutureCalls()
    public static integer  EmailPerTransaction_LIMIT       = Limits.getLimitEmailInvocations(); // getEmailInvocations()
    public static integer  DMLPerTransaction_LIMIT         = Limits.getLimitDmlRows(); // getDMLStatements()
    public static integer  RowsPerTransaction_LIMIT        = Limits.getLimitQueryRows(); // getQueryRows()
    private static integer DATA_BATCH_SIZE                 = DMLPerTransaction_LIMIT;

    // Primary variables
    public static List<SObject> Objects = new List<SObject>();
    public static Set<ID> IDsAlreadyMarkedForProcessing = new Set<ID>();
    public static Set<ID> IDsToProcess = new Set<ID>();
    public static String query;
    public static integer TotalNumberOfRecords = 0;
    public static boolean SomethingToUpdate = true;
    private static integer TotalFutureCallsNeeded = 0;
    private static integer TotalFutureCallsExcecuted = 0;

    private static Map<Id,MassRecordUpdater_Objects__mdt> APINamesMap;
    private static Set<ID> CustomMetaObjectsIDs = new Set<ID>();
    private static List<String> APINames = new List<String>();
    private static List<MassRecordUpdater_Process__mdt> processDefinition;

    public MassRecordUpdaterClass() {
        // Set limit values
        QueriesPerTransaction_LIMIT     = Limits.getLimitQueryRows(); // getQueryRows() 
        FuturePerTransaction_LIMIT      = Limits.getLimitFutureCalls(); //getFutureCalls()
        EmailPerTransaction_LIMIT       = Limits.getLimitEmailInvocations(); // getEmailInvocations()
        DMLPerTransaction_LIMIT         = Limits.getLimitDmlRows(); // getDMLStatements()
        RowsPerTransaction_LIMIT        = Limits.getLimitQueryRows(); // getQueryRows()
    }

    public static void execute () 
    { 
        // List of API Names for object considered
        APINamesMap   = new Map<Id,MassRecordUpdater_Objects__mdt>([SELECT ID, Object_API_Name__c FROM MassRecordUpdater_Objects__mdt]);
        system.debug('APINamesMap: ' + APINamesMap);
        // Get the record count for each object
        for (ID key : APINamesMap.keyset()) {
            system.debug('key: ' + key);
            system.debug('APINamesMap.get(Key).Object_API_Name__c: ' + APINamesMap.get(Key).Object_API_Name__c);
            // How many total records 
            TotalNumberOfRecords += NumberOfRecords(APINamesMap.get(Key).Object_API_Name__c); 
            // Break values apart so we can pass them to future method
            APINames.add(APINamesMap.get(Key).Object_API_Name__c);
            CustomMetaObjectsIDs.Add(Key);
        }   

         // How many future calls will we need
        TotalFutureCallsNeeded = (TotalNumberOfRecords/DMLPerTransaction_LIMIT);

        // Ensure we are making at least one future call
        TotalFutureCallsNeeded = ((DMLPerTransaction_LIMIT - TotalNumberOfRecords) > 0 ) ? TotalFutureCallsNeeded = TotalFutureCallsNeeded + 1 : TotalFutureCallsNeeded;
        
        // Make sure we are within future call limits
        TotalFutureCallsNeeded = (TotalFutureCallsNeeded > FuturePerTransaction_LIMIT) ? FuturePerTransaction_LIMIT : TotalFutureCallsNeeded;

        system.debug('TotalFutureCallsNeeded: ' + TotalFutureCallsNeeded);

        for (String APIName : APINames) {
            for (ID CustomMetaObjectsID : CustomMetaObjectsIDs) {
                //Grab a batch of IDs
                if (IDsAlreadyMarkedForProcessing.size() < 1) {

                    // final form looks like SELECT ID FROM Account LIMIT 10000 with account and LIMIT number changable
                    query = 'SELECT ID FROM ' + APIName + ' LIMIT ' + DMLPerTransaction_LIMIT;
                }
                else {
                    query = 'SELECT ID FROM ' + APIName +  ' WHERE ID NOT IN :IDsAlreadyMarkedForProcessing LIMIT ' + DMLPerTransaction_LIMIT;
                }

                Objects = database.query(query);
                IDsToProcess.clone();
                for(SObject obj : Objects) 
                    IDsToProcess.add(obj.id);
                system.debug('APIName: ' + APIName);
                system.debug('CustomMetaObjectsID: ' + CustomMetaObjectsID);
                ProcessRecords(CustomMetaObjectsID,APIName,IDsToProcess);
                TotalFutureCallsExcecuted++; // count it!

                for(SObject obj : Objects)  {
                    IDsAlreadyMarkedForProcessing.add(obj.id);
                }
                if (TotalFutureCallsExcecuted > TotalFutureCallsNeeded) break; // leave inner loop
            }
            if (TotalFutureCallsExcecuted > TotalFutureCallsNeeded) break; // leave outer loop
        }
    }

    private static Map<Id, MassRecordUpdater_Objects__mdt> getObjectApiNames() 
    {
        Map<Id,MassRecordUpdater_Objects__mdt> APINames;
        try {
                APINames = 
                    new Map<Id,MassRecordUpdater_Objects__mdt>([SELECT Id, Object_API_Name__c FROM MassRecordUpdater_Objects__mdt]);

                if (APINames == null) throw new MassRecordUpdaterClassException('getObjectApiNames APINames is NULL'); 
            
            return APINames;
        
        } catch (Exception e) {
            // error logging
            system.debug('getObjectApiNames: ' + e.getMessage());
            return APINames;
        }
    }

    private static integer NumberOfRecords (String ObjectAPIName) {
        String query;
        Integer result;
        try {
            query = 'SELECT count() FROM ' + objectAPIName;
            result = Database.countQuery(query);

            return result;

        } catch (Exception e) {
            // error logging
            system.debug('NumberOfRecords: ' + e.getMessage());
            return -1;
        }
    }

     

    @future 
    private static void ProcessRecords(ID CustomMetaDataRecord, String APIName, Set<ID> IDsToProcess)
    {
        String query;
        List<SObject> objects;
        try {

            system.debug('CustomMetaDataRecord: ' + CustomMetaDataRecord);
            system.debug('APIName: ' + APIName);
            system.debug('IDsToProcess: ' + IDsToProcess);
            // Get related fields
            List<MassRecordUpdater_Process__mdt> processDefinitions = [SELECT Require_Criteria__c, New_Field_Value__c, MassRecordUpdater_Object__c,Field_API_Name__c, Current_Field_Value__c FROM MassRecordUpdater_Process__mdt WHERE MassRecordUpdater_Object__c =:CustomMetaDataRecord];



            query = 'SELECT ';
            for (MassRecordUpdater_Process__mdt processDefinition : processDefinitions) {
                query = query + processDefinition.Field_API_Name__c + ', ';
            }
            system.debug('1 query: ' + query);
            query = query.removeEnd(', ');
            system.debug('2 query: ' + query);

            query = query + ' FROM ' + APIName + ' WHERE ID IN: IDsToProcess LIMIT ' + DMLPerTransaction_LIMIT;

            system.debug('future query: ' + query);

            objects = Database.query(query);

            for (SObject obj : objects) {
                system.debug('obj: ' + obj);
                for (MassRecordUpdater_Process__mdt processDefinition : processDefinitions)
                    obj.put(processDefinition.Field_API_Name__c,processDefinition.New_Field_Value__c);
            }
            update objects;

        } catch (Exception e) {
            system.debug('ProcessRecords - TestProcessing: ' + e.getMessage());
        }

    }
}