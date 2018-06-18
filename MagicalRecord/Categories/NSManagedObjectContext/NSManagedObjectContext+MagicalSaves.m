//
//  NSManagedObjectContext+MagicalSaves.m
//  Magical Record
//
//  Created by Saul Mora on 3/9/12.
//  Copyright (c) 2012 Magical Panda Software LLC. All rights reserved.
//

#import "NSManagedObjectContext+MagicalSaves.h"
#import "MagicalRecord+ErrorHandling.h"
#import "NSManagedObjectContext+MagicalRecord.h"
#import "MagicalRecord.h"

@implementation NSManagedObjectContext (MagicalSaves)

- (void)MR_saveOnlySelfWithCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:0 completion:completion];
}

- (void)MR_saveOnlySelfAndWait;
{
    [self MR_saveWithOptions:MRSaveSynchronously completion:nil];
}

- (void) MR_saveToPersistentStoreWithCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:MRSaveParentContexts completion:completion];
}

- (void) MR_saveToPersistentStoreAndWait;
{
    [self MR_saveWithOptions:MRSaveParentContexts | MRSaveSynchronously completion:nil];
}

- (void)MR_saveWithOptions:(MRSaveContextOptions)mask completion:(MRSaveCompletionHandler)completion;
{
    BOOL syncSave           = ((mask & MRSaveSynchronously) == MRSaveSynchronously);
    BOOL saveParentContexts = ((mask & MRSaveParentContexts) == MRSaveParentContexts);

    __block BOOL hasChanges = NO;
    __block NSString *workingName = nil;
    __block NSManagedObjectContext *parentContext = nil;
    
    [self performBlockAndWait:^{
        hasChanges = [self hasChanges];
        workingName = [self MR_workingName];
        if (saveParentContexts) {
            parentContext = [self parentContext];
        }
    }];
    

    if (!hasChanges) {
        MRLog(@"NO CHANGES IN ** %@ ** CONTEXT - NOT SAVING", workingName);

        if (saveParentContexts && parentContext)
        {
            MRLog(@"Proceeding to save parent context %@", [parentContext MR_description]);
        }
        else
        {
            if (completion)
            {
                completion(YES, nil);
            }
            
            return;
        }
    }

    void (^saveBlock)(void) = ^{
        NSString *optionsSummary = @"";
        optionsSummary = [optionsSummary stringByAppendingString:saveParentContexts ? @"Save Parents," : @""];
        optionsSummary = [optionsSummary stringByAppendingString:syncSave ? @"Sync Save" : @""];
        
        MRLog(@"→ Saving %@ [%@]", [self MR_description], optionsSummary);
        
        NSError *error = nil;
        BOOL saved = NO;
        
        @try
        {
            saved = [self save:&error];
        }
        @catch (NSException *exception)
        {
            MRLogError(@"Unable to perform save: %@", (id)[ exception userInfo ] ?: (id)[ exception reason ]);
        }
        @finally
        {
            if (!saved)
            {
                [MagicalRecord handleErrors:error];
                
                if (completion)
                {
                    completion(saved, error);
                }
            }
            else
            {
                // If we should not save the parent context, or there is not a parent context to save (root context), call the completion block
                if ((YES == saveParentContexts) && [self parentContext])
                {
                    MRSaveContextOptions parentContentSaveOptions = (MRSaveContextOptions)(MRSaveParentContexts | MRSaveSynchronously);
                    [[self parentContext] MR_saveWithOptions:parentContentSaveOptions completion:completion];
                }
                // If we are not the default context (And therefore need to save the root context, do the completion action if one was specified
                else
                {
                    MRLog(@"→ Finished saving: %@", [self MR_description]);
                    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
                    NSUInteger numberOfInsertedObjects = [[self insertedObjects] count];
                    NSUInteger numberOfUpdatedObjects = [[self updatedObjects] count];
                    NSUInteger numberOfDeletedObjects = [[self deletedObjects] count];
#pragma clang diagnostic pop
                    
                    MRLog(@"Objects - Inserted %tu, Updated %tu, Deleted %tu", numberOfInsertedObjects, numberOfUpdatedObjects, numberOfDeletedObjects);
                    
                    if (completion)
                    {
                        completion(saved, error);
                    }
                }
            }
        }
    };
    
    if (YES == syncSave)
    {
        [self performBlockAndWait:saveBlock];
    }
    else
    {
        [self performBlock:saveBlock];
    }
}

#pragma mark - Deprecated methods
// These methods will be removed in MagicalRecord 3.0

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (void)MR_save;
{
    [self MR_saveToPersistentStoreAndWait];
}

- (void)MR_saveWithErrorCallback:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveWithOptions:MRSaveSynchronously|MRSaveParentContexts completion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveInBackgroundCompletion:(void (^)(void))completion;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        }
    }];
}

- (void)MR_saveInBackgroundErrorHandler:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveInBackgroundErrorHandler:(void (^)(NSError *error))errorCallback completion:(void (^)(void))completion;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        } else {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveNestedContexts;
{
    [self MR_saveToPersistentStoreWithCompletion:nil];
}

- (void)MR_saveNestedContextsErrorHandler:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveNestedContextsErrorHandler:(void (^)(NSError *error))errorCallback completion:(void (^)(void))completion;
{
    [self MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        } else {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

#pragma clang diagnostic pop // ignored "-Wdeprecated-implementations"

@end
