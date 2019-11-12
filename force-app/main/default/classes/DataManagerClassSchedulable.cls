global without sharing class DataManagerClassSchedulable implements Schedulable {
   string ProcessLabel = '';
   global DataManagerClassSchedulable (String name) {
      ProcessLabel = name;
   }     
   global void execute(SchedulableContext SC) {
           DataManagerClass.execute(ProcessLabel);
   }
}