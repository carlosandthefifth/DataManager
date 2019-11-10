global without sharing class MassRecordUpdateClassSchedulable implements Schedulable {
   global void execute(SchedulableContext SC) {
           MassRecordUpdaterClass.execute();
   }
}
