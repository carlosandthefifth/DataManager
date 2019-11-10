public class custommetadata {
    static sObject anObject;
        public static void updateObject () {
            Map<Id,MassRecordUpdater_Objects__mdt> apiNames = 
                new Map<Id,MassRecordUpdater_Objects__mdt>([SELECT Id, Object_API_Name__c FROM MassRecordUpdater_Objects__mdt]);
            MassRecordUpdater_Process__mdt processDefinition = 
                [SELECT Require_Criteria__c, New_Field_Value__c, MassRecordUpdater_Object__c,Field_API_Name__c, Current_Field_Value__c FROM MassRecordUpdater_Process__mdt];
            
            system.debug('apiNames: ' + apiNames);
            system.debug('processDefinition: ' + processDefinition);
            system.debug('apiName is: ' + apiNames.get(processDefinition.MassRecordUpdater_Object__c).Object_API_Name__c);
            
            String query = 'SELECT ' + processDefinition.Field_API_Name__c + ' FROM ' + apiNames.get(processDefinition.MassRecordUpdater_Object__c).Object_API_Name__c;
            
            system.debug('query: ' + query);
            
            sObject anObject = database.query(query);
            system.debug('anObject: ' + anObject);
            system.debug('anObject field: ' + anObject.get(processDefinition.Field_API_Name__c));
            anObject.put(processDefinition.Field_API_Name__c, processDefinition.New_Field_Value__c);
            
            update anObject;
            
            
        }
 }