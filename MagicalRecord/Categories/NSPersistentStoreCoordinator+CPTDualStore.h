//
//  NSPersistentStoreCoordinator+CPTDualStore.h
//  PainTracker
//
//  Created by Bob Kutschke on 6/30/12.
//  Copyright (c) 2012 Chronic Stimulation, LLC. All rights reserved.
//

#import <CoreData/CoreData.h>

extern NSString * const kMagicalRecordPSCWillBeginDBMigrationNotification;
extern NSString * const kMagicalRecordPSCDidCompleteDBMigrationNotification;
extern NSString * const kMagicalRecordPSCDidFailDBMigrationNotification;

@interface NSPersistentStoreCoordinator (CPTDualStore)

+(NSPersistentStoreCoordinator*)defaultCoordinator;
+(NSString *)primaryDiaryStorePath;
+(NSString *)pathComponentToExternalStorage;
+(NSString *)primaryDiaryStoreExternalDataPath;
+(NSString *)reportDataStorePath;
-(void)addCPTStores;
-(void)removeCPTStores;

@end
