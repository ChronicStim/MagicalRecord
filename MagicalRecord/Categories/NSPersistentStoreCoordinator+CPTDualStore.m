//
//  NSPersistentStoreCoordinator+CPTDualStore.m
//  PainTracker
//
//  Created by Bob Kutschke on 6/30/12.
//  Copyright (c) 2012 Chronic Stimulation, LLC. All rights reserved.
//

#import "NSPersistentStoreCoordinator+CPTDualStore.h"

#define DEFAULT_CACHE_FOLDER_NAME @"CPT_RptDatabase_Cache"

#define kPSCStoreFilenameDiary @"CPT_PrimaryDiary.sqlite"
#define kPSCStoreFilenameReports @"CPT_ReportData.sqlite"
#define kPSCConfigurationDiary @"DiaryModel"
#define kPSCConfigurationReports @"DiaryReportsModel"
#define kPrefLastVersionRunKey @"!prefLastVersionRun"

@implementation NSPersistentStoreCoordinator (CPTDualStore)

static NSPersistentStoreCoordinator* _persistentStoreCoordinator = nil;

+(NSString *)primaryDiaryStorePath;
{
    static NSString *storeFilename = kPSCStoreFilenameDiary;
    NSString *appDocumentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ( ![fileManager fileExistsAtPath:appDocumentsDirectory isDirectory:NULL] ) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:appDocumentsDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
            DDLogError(@"Failed to create application directory: %@ Error: %@", appDocumentsDirectory,[error userInfo]);
            return nil;
        }
    }

    NSString *storePath = [appDocumentsDirectory stringByAppendingPathComponent: storeFilename];
    return storePath;
}

+(NSString *)reportDataStorePath;
{
    static NSString *storeFilename = kPSCStoreFilenameReports;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *cacheFolderPath = [cacheDirectory stringByAppendingPathComponent:DEFAULT_CACHE_FOLDER_NAME];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ( ![fileManager fileExistsAtPath:cacheFolderPath isDirectory:NULL] ) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:cacheFolderPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            DDLogError(@"Failed to create report data cache directory: %@ Error: %@", cacheFolderPath,[error userInfo]);
            return nil;
        }
    }
    NSString *storePath = [cacheFolderPath stringByAppendingPathComponent: storeFilename];
    return storePath;
}

+(NSPersistentStoreCoordinator*)defaultCoordinator;
{
    if (_persistentStoreCoordinator == nil) {
        
        NSManagedObjectModel *mom = [NSManagedObjectModel MR_defaultManagedObjectModel];
        if (!mom) {
            //NSAssert(NO, @"NSManagedObjectModel is nil");
            DDLogError(@"%@: No model to generate a store from", [self class]);
            return nil;
        }
        
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
        
    }
    
    NSArray *currentStores = [_persistentStoreCoordinator persistentStores];
    if ([currentStores count] == 0) {
        [_persistentStoreCoordinator addCPTStores];
    }
    
    return _persistentStoreCoordinator;
}

-(void)addCPTStores;
{
    static NSString *storeFilename = kPSCStoreFilenameDiary;
    static NSString *storeFilenameReportData = kPSCStoreFilenameReports;
    
    NSArray *storeArray = [NSArray arrayWithObjects:storeFilename,storeFilenameReportData, nil];
    
    DDLogInfo(@"Active database for newPSC = %@",storeFilename);
    DDLogInfo(@"Active database for newPSC = %@",storeFilenameReportData);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSString *filename in storeArray) {
        
        NSString *configuration;
        NSString *storePath;
        if ([filename isEqualToString:kPSCStoreFilenameDiary]) {
            configuration = kPSCConfigurationDiary;
            storePath = [NSPersistentStoreCoordinator primaryDiaryStorePath];
        } else if ([filename isEqualToString:kPSCStoreFilenameReports]) {
            configuration = kPSCConfigurationReports;
            storePath = [NSPersistentStoreCoordinator reportDataStorePath];
        } else {
            configuration = nil;
            storePath = nil;
        }
        NSURL *storeUrl = [NSURL fileURLWithPath: storePath];
        
        // Check if a previously failed migration has left a *.new store in the filesystem. If it has, then remove it before the next migration.
        NSString *storePathNew = [storePath stringByAppendingPathExtension:@"new"];
        if ([fileManager fileExistsAtPath:storePathNew]) {
            NSError *errorNewRemoval = nil;
            if (![fileManager removeItemAtPath:storePathNew error:&errorNewRemoval]) {
                DDLogError(@"Removal of %@.new file was not successful",filename);
            }
        }
        
        // Need to see if the database files exist or not
        BOOL databaseFileExists = [fileManager fileExistsAtPath:storePath];
        if (databaseFileExists) {
            // If file exists, compatibility needs to be checked.
            NSString *sourceStoreType = NSSQLiteStoreType;
            NSError *errorCompatibility = nil;
            NSDictionary *sourceMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:sourceStoreType URL:storeUrl error:&errorCompatibility];
            
            if (sourceMetadata == nil) {
                // deal with error
                DDLogError(@"Could not retrieve metadata from the store: %@ with Error: %@",storeFilename,[errorCompatibility userInfo]);
            }
            
            NSManagedObjectModel *destinationModel = [self managedObjectModel];
            BOOL pscCompatibile = [destinationModel isConfiguration:configuration compatibleWithStoreMetadata:sourceMetadata];
            
            // If not compatible, then need to try to migrate using the workaround process.
            BOOL migrationWorkaroundHasBeenRun = NO;
            if (!pscCompatibile) {
                
                while (!migrationWorkaroundHasBeenRun) {
                    
                    NSString *dummyPSCString = @"dummyPSC";
                    
                    NSString *lastVersionRun;
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    if ([defaults objectForKey:kPrefLastVersionRunKey]) {
                        lastVersionRun = [defaults objectForKey:kPrefLastVersionRunKey];
                    } else {
                        lastVersionRun = @"";
                    }
                    
                    NSString *versionString;
                    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                    versionString = [NSString stringWithFormat:@"v%@",ver];
                    
                    NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Running workaround.",lastVersionRun,versionString,filename];
                    DDLogInfo(@"Running migration workaround to try and bypass incompatibility. %@",message);
                    
                    DDLogInfo(@"Active database for %@ = %@",dummyPSCString,filename);
                                        
                    NSURL *storeUrl = [NSURL fileURLWithPath: storePath];
                    NSPersistentStoreCoordinator *dummyPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:destinationModel];
                    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],NSMigratePersistentStoresAutomaticallyOption,[NSNumber numberWithBool:YES],NSInferMappingModelAutomaticallyOption,nil];
                    NSError *error = nil;
                    if (![dummyPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:options error:&error]) {
                        DDLogError(@"Core Data Error:%@ : %@",[error localizedDescription],[error userInfo]);
                        NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Failed workaround.",lastVersionRun,versionString,filename];
                        DDLogError(@"Failed to resolve migration issue. %@",message);
                    } else {
                        NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Migration workaround succeeded.",lastVersionRun,versionString,filename];
                        DDLogInfo(@"Migration issue resolved. %@",message);
                    }
                    dummyPSC=nil;
                    migrationWorkaroundHasBeenRun = YES;
                }
            }
        }
        
        // Proceed with store assignment
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],NSMigratePersistentStoresAutomaticallyOption,[NSNumber numberWithBool:YES],NSInferMappingModelAutomaticallyOption,nil];
        NSError *error = nil;
        // Check if a store at the url has already been assigned to the controller
        if (![self persistentStoreForURL:storeUrl]) {
            if (![self addPersistentStoreWithType:NSSQLiteStoreType configuration:configuration URL:storeUrl options:options error:&error]) {
                DDLogError(@"Core Data Error:%@ : %@",[error localizedDescription],[error userInfo]);
            } else {
                DDLogInfo(@"Added PersistentStore at URL: %@",storeUrl);
            }
        }
    }
}

-(void)removeCPTStores;
{
    NSArray *storeArray = [NSArray arrayWithObjects:[NSURL fileURLWithPath:[NSPersistentStoreCoordinator primaryDiaryStorePath]],[NSURL fileURLWithPath:[NSPersistentStoreCoordinator reportDataStorePath]], nil];
   
    for (NSURL *storeURL in storeArray) {
        NSPersistentStore *store = [self persistentStoreForURL:storeURL];
        NSError *error = nil;
        if (![self removePersistentStore:store  error:&error]) {
            DDLogError(@"Error removing store at URL: %@  Error: %@",storeURL,[error userInfo]);
        } else {
            DDLogInfo(@"PersistentStore has been removed from Coordinator; URL = %@",storeURL);
        }
    }
}

@end
