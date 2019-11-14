global without sharing class DataManagerClassSchedulable implements Schedulable {
   string ProcessLabel = '';

   global DataManagerClassSchedulable (String name) {
      ProcessLabel = name;
   }     

   global void execute(SchedulableContext SC) {
      if (ProcessLabel != '')
         DataManagerClass.execute(ProcessLabel);
      else {
         DataManagerClass.execute();
      }
   }
}