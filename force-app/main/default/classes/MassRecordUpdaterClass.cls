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
public without sharing class MassRecordUpdaterClass {

    
    public class DataManagerClassException extends Exception {}

    public static boolean ThrowException_CodeCoverage = false;

    // LIMITS SECTION
    public static integer  QueriesPerTransaction_LIMIT     = Limits.getLimitQueryRows(); // getQueryRows() 
    public static integer  FuturePerTransaction_LIMIT      = Limits.getLimitFutureCalls(); //getFutureCalls()
    public static integer  EmailPerTransaction_LIMIT       = Limits.getLimitEmailInvocations(); // getEmailInvocations()
    public static integer  DMLPerTransaction_LIMIT         = Limits.getLimitDmlRows(); // getDMLStatements()
    public static integer  RowsPerTransaction_LIMIT        = Limits.getLimitQueryRows(); // getQueryRows()
    private static integer DATA_BATCH_SIZE                 = DMLPerTransaction_LIMIT;

    // Primary variables
    public static List<Data_Manager_Project__mdt>  projects = new List<Data_Manager_Project__mdt>();
    public static List<SObject> Objects = new List<SObject>();
    public static Set<ID> IDsAlreadyMarkedForProcessing = new Set<ID>();
    public static Set<ID> IDsToProcess = new Set<ID>();
    public static String query;
    public static integer TotalNumberOfRecords = 0;
    public static boolean SomethingToUpdate = true;
    private static integer TotalFutureCallsNeeded = 0;
    private static integer TotalFutureCallsExecuted = 0;

    private static Map<Id,Data_Manager_Object__mdt> APIObjectNamesMap;
    private static Set<ID> CustomMetaObjectsIDs = new Set<ID>();
    private static List<String> APINames = new List<String>();
 
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
        Set<ID>ProjectIDs = new Set<ID>();
        Integer TotalRecords = 0;
        // List of active projects 
        string query = 'SELECT ID, Verb__c FROM Data_Manager_Project__mdt WHERE Active__c = true LIMIT ' + RowsPerTransaction_LIMIT;
        system.debug('query: ' + query);
        projects = Database.query(query);
        
        // Aggregate all ids for active projects
        for (Data_Manager_Project__mdt project : projects) 
            ProjectIds.add(project.id);

        system.debug('projects.size(): ' + projects.size());
        // List of Object API Names 
        query = 'SELECT ID, Object_API_Name__c, Record_Count__c FROM Data_Manager_Object__mdt WHERE Data_Manager_ProjectId__c IN :ProjectIds';

        system.debug('query: ' + query);
        APIObjectNamesMap   = new Map<Id,Data_Manager_Object__mdt>((List<Data_Manager_Object__mdt>)database.query(query));  
        for (Data_Manager_Project__mdt project : projects) {
            for (ID key : APIObjectNamesMap.keyset()) {
                //Grab a batch of IDs
                if (IDsAlreadyMarkedForProcessing.size() < 1) {
                    // final form looks like SELECT ID FROM Account LIMIT 10000 with account and LIMIT number changable
                    query = 'SELECT ID FROM ' + APIObjectNamesMap.get(Key).Object_API_Name__c  + ' LIMIT ' + DMLPerTransaction_LIMIT;
                }
                else {
                    query = 'SELECT ID  FROM ' + APIObjectNamesMap.get(Key).Object_API_Name__c + ' WHERE ID NOT IN :IDsAlreadyMarkedForProcessing LIMIT ' + DMLPerTransaction_LIMIT;
                }

                system.debug('query: ' + query);
                Objects = database.query(query);
                if  (project.Verb__c == 'Update' || project.Verb__c == 'Upsert') {
                    IDsToProcess.clear();
                    for(SObject obj : Objects) 
                        IDsToProcess.add(obj.id);

                    TotalRecords = IDsToProcess.size();
                } else {
                    TotalRecords = (Integer)APIObjectNamesMap.get(key).Record_Count__c;
                }
                system.debug('APIObjectNamesMap.get(Key).Object_API_Name__c: ' + APIObjectNamesMap.get(Key).Object_API_Name__c);
                system.debug('key: ' + key);


                // How many future calls will we need
                TotalFutureCallsNeeded = (TotalRecords/DMLPerTransaction_LIMIT);

                // Ensure we are making at least one future call
                TotalFutureCallsNeeded = ((DMLPerTransaction_LIMIT - TotalNumberOfRecords) > 0 ) ? TotalFutureCallsNeeded = TotalFutureCallsNeeded + 1 : TotalFutureCallsNeeded;
            
                // Make sure we are within future call limits
                TotalFutureCallsNeeded = (TotalFutureCallsNeeded > FuturePerTransaction_LIMIT) ? FuturePerTransaction_LIMIT : TotalFutureCallsNeeded;

                system.debug('TotalFutureCallsNeeded: ' + TotalFutureCallsNeeded);

                TotalFutureCallsExecuted = 0;
                while (TotalFutureCallsExecuted < TotalFutureCallsNeeded) {
                    if (project.Verb__c == 'Update' || project.Verb__c == 'Upsert') {
                        ProcessRecords(Project.id,key,APIObjectNamesMap.get(Key).Object_API_Name__c,IDsToProcess,Project.Verb__c,0);
                    } else {
                        ProcessRecords(Project.id,key,APIObjectNamesMap.get(Key).Object_API_Name__c,IDsToProcess,Project.Verb__c,(Integer)APIObjectNamesMap.get(key).Record_Count__c);
                    }

                    TotalFutureCallsExecuted++; // count it!
                }

                for(SObject obj : Objects)  {
                    IDsAlreadyMarkedForProcessing.add(obj.id);
                }
            }
        }
    }

    private static Map<Id, Data_Manager_Object__mdt> getObjectApiNames() 
    {
        Map<Id,Data_Manager_Object__mdt> APINames;
        try {
                APINames = 
                    new Map<Id,Data_Manager_Object__mdt>([SELECT Id, Object_API_Name__c FROM Data_Manager_Object__mdt]);

                if (APINames == null) throw new DataManagerClassException('getObjectApiNames APINames is NULL'); 
            
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
    private static void ProcessRecords(ID ProjectId, ID CustomMetaDataRecord, String APIName, Set<ID> IDsToProcess, String verb, Integer RecordCount)
    {
        String query;
        List<SObject> objects;
        try {
            system.debug('CustomMetaDataRecord: ' + CustomMetaDataRecord);
            system.debug('APIName: ' + APIName);
            system.debug('IDsToProcess: ' + IDsToProcess);
            if (verb == 'Update' || verb == 'Upsert') {

                // Get related fields
                query = 'SELECT API_Field_Name__c, New_Value__c FROM Data_Manager_Field__mdt WHERE Data_Manager_ObjectId__c = \''+ CustomMetaDataRecord + '\'';
                system.debug('query: ' + query);

                List<Data_Manager_Field__mdt> fields = database.Query(query);

                system.debug('fields: ' + fields);

                //build query 
                query = 'SELECT ';
                for (Data_Manager_Field__mdt field : fields) {
                    query = query + field.API_Field_Name__c + ', ';
                }
                system.debug('1 query: ' + query);
                query = query.removeEnd(', ');
                system.debug('2 query: ' + query);

                query = query + ' FROM ' + APIName + ' WHERE ID IN: IDsToProcess LIMIT ' + DMLPerTransaction_LIMIT;

                system.debug('3 query: ' + query);

                objects = Database.query(query);
                for (SObject obj : objects) {
                    system.debug('obj: ' + obj);
                    for (Data_Manager_Field__mdt field : fields)
                        obj.put(field.API_Field_Name__c,field.New_Value__c);
                }
                update objects;
            } else {
                // Insert
                objects = new List<SObject>();
                query = 'SELECT API_Field_Name__c, New_Value__c, Suffix_Iterator__c FROM Data_Manager_Field__mdt WHERE Data_Manager_ObjectId__c = \''+ CustomMetaDataRecord + '\'';
                system.debug('query: ' + query);

                List<Data_Manager_Field__mdt> fields = database.Query(query);

                for (Integer i = 0; i< RecordCount;i++){
                    SObject obj =  (SObject)Type.forName(APIName).newInstance();
                    for (Data_Manager_Field__mdt field : fields) {                        
                        if (field.Suffix_Iterator__c) { 
                            system.debug('iterator true');
                            obj.put(field.API_Field_Name__c,field.New_Value__c + ' ' + i);
                        }
                        else {
                            system.debug('iterator false');
                            obj.put(field.API_Field_Name__c,field.New_Value__c);
                        }
                    }
                    system.debug('obj: ' + obj);
                    objects.add(obj);
                    system.debug('objects: ' + objects);

                }
                insert objects;
            }

        } catch (Exception e) {
            system.debug('ProcessRecords - TestProcessing: ' + e.getMessage());
        }

    }
}