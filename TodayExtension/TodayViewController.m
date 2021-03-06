//
//  TodayViewController.m
//  TodayExtension
//
//  Created by Philippe Boudreau on 2014-11-05.
//  Copyright (c) 2014 Fasterre. All rights reserved.
//

#import "TodayViewController.h"
#import <NotificationCenter/NotificationCenter.h>

#import "FSCHarmonyCommon.h"
#import "FSCDataSharingController.h"
#import "FSCControlGroup.h"
#import "UIImage+Mask.h"

static CGFloat const activityCellDim = 75.0;

static NSArray * viewsForStatePreservation = nil;

static NSString * const standardDefaultsKeyViewStatePreservationAlpha = @"viewStatePreservation-alpha-";

static CGFloat const backwardForwardGestureMinimumDelta = 5.0;

@interface TodayViewController () <NCWidgetProviding>
{
    BOOL playToggle;
    BOOL repeatFunction;
    BOOL gestureHandled;
    CGPoint backwardForwardGestureInitialLocation;
}

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *activityCollectionViewHeightConstraint;

@property (weak, nonatomic) IBOutlet UIView *staticActivitiesView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *staticActivitiesViewHeightConstraint;

@property (weak, nonatomic) IBOutlet UIView *volumeView;
@property (weak, nonatomic) IBOutlet UIButton *volumeDownButton;
@property (weak, nonatomic) IBOutlet UIButton *volumeUpButton;

@property (weak, nonatomic) IBOutlet UIView *transportView;
@property (strong, nonatomic) IBOutlet UITapGestureRecognizer *playPauseTapGesture;
@property (strong, nonatomic) IBOutlet UILongPressGestureRecognizer *backwardForwardLongPressGesture;
@property (strong, nonatomic) IBOutlet UILongPressGestureRecognizer *backwardForwardRepeatLongPressGesture;

@property (weak, nonatomic) IBOutlet UIView *powerOffView;
@property (weak, nonatomic) IBOutlet UIImageView *powerOffIconImageView;
@property (weak, nonatomic) IBOutlet UILabel *powerOffLabel;

@property (weak, nonatomic) IBOutlet UILabel *statusLabel;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;

@end

@implementation TodayViewController

#pragma mark - Superclass Methods

- (void) viewDidLoad
{
    [super viewDidLoad];
    
    for (UIView * aView in @[[self volumeDownButton],
                             [self volumeUpButton],
                             [self transportView]])
    {
        [[aView layer] setCornerRadius: 5.0];
        [[aView layer] setBorderWidth: 1.0];
        [[aView layer] setBorderColor: [[UIColor whiteColor] CGColor]];
    }
    
    playToggle = NO;
    
    [[self playPauseTapGesture] requireGestureRecognizerToFail: [self backwardForwardLongPressGesture]];
    [[self playPauseTapGesture] requireGestureRecognizerToFail: [self backwardForwardRepeatLongPressGesture]];
    
    UIImage * powerOffImage = [UIImage imageNamed: @"activity_powering_off"];
    UIImage * maskedPowerOffImage = [powerOffImage convertToInverseMaskWithColor: [self colorForActivityMask]];
    [[self powerOffIconImageView] setImage: maskedPowerOffImage];
    
    viewsForStatePreservation = @[@"staticActivitiesView",
                                  @"volumeView",
                                  @"transportView",
                                  @"powerOffView"];
    
    [self loadUIState];
    
    [self loadConfiguration];
    
    [self updateContentLayout];
}

- (void) viewDidAppear: (BOOL) animated
{
    [super viewDidAppear: animated];
    
    if ([self client])
    {
        [[self client] connect];
    }
}

- (void) viewDidDisappear: (BOOL) animated
{
    [super viewDidDisappear: animated];
    
    [self saveUIState];
    
    if ([self client])
    {
        [[self client] disconnect];
    }
}

- (UIEdgeInsets) widgetMarginInsetsForProposedMarginInsets: (UIEdgeInsets) defaultMarginInsets
{
    return UIEdgeInsetsZero;
}

- (NSArray *) activities
{
    NSArray * allActivities = [[self harmonyConfiguration] activity];
    
    return [allActivities subarrayWithRange: NSMakeRange(0, [allActivities count] - 1)];
}

- (void) setHarmonyConfiguration: (FSCHarmonyConfiguration *) harmonyConfiguration
{
    [super setHarmonyConfiguration: harmonyConfiguration];
    
    NSString * statusLabelText = @"";
    
    if (![self harmonyConfiguration])
    {
        statusLabelText = NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-NO_HARMONY_CONFIGURATION", nil);
    }
    
    [[self statusLabel] setText: statusLabelText];
}

- (void) clientSetupBegan
{
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        [[self activityIndicatorView] startAnimating];
        [[self statusLabel] setText: NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-CONNECTING", nil)];
    });
}

- (void) clientSetupEnded
{
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        [[self activityIndicatorView] stopAnimating];
        [[self statusLabel] setText: nil];
    });
}

- (void) handleCurrentActivityChanged: (FSCActivity *) newActivity
{
    [super handleCurrentActivityChanged: newActivity];
    
    [self updateUIForCurrentActivity: newActivity];
}

- (void) prepareForBlockingClientAction
{
    [super prepareForBlockingClientAction];
    
    [[self view] setUserInteractionEnabled: NO];
}

- (void) cleanupAfterBlockingClientActionWithError: (NSError *) error
{
    [super cleanupAfterBlockingClientActionWithError: error];
    
    NSString * statusLabelText = nil;
    
    if (error)
    {
        NSString * originalError = nil;
        
        if ([error userInfo] &&
            (originalError = [[error userInfo] objectForKey: FSCErrorUserInfoKeyOriginalError]) &&
            ([originalError isEqualToString: FSCErrorHarmonyXMPPNetworkUnreachable] ||
             [originalError isEqualToString: FSCErrorHarmonyXMPPConnectionRefused]))
        {
            [[self activityIndicatorView] stopAnimating];
         
            if ([originalError isEqualToString: FSCErrorHarmonyXMPPNetworkUnreachable])
            {
                statusLabelText = NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-NOT_NETWORK_CONNECTIVITY", nil);
            }
            else
            {
                statusLabelText = NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-NO_HARMONY_HUB_FOUND_ON_NETWORK", nil);
            }
        }
        else if ([error code] == FSCErrorCodeMissingSetup)
        {
            statusLabelText = NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-NO_HARMONY_CONFIGURATION", nil);
        }
        else if ([error code] == FSCErrorCodeMissingCredentials)
        {
            statusLabelText = NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-INVALID_IP_PORT", nil);
        }
        else
        {
            statusLabelText = [error localizedDescription];
        }
    }
    
    [[self statusLabel] setText: statusLabelText];
    
    [[self view] setUserInteractionEnabled: YES];
}

- (UIColor *) colorForActivityMask
{
    return [UIColor whiteColor];
}

- (UIColor *) inverseColorForActivityMask
{
    return [UIColor blackColor];
}

- (UIColor *) backgroundColorForInverseActivityMask
{
    return [UIColor whiteColor];
}

#pragma mark - Class Methods

- (void) loadUIState
{
    NSUserDefaults * standardDefaults = [NSUserDefaults standardUserDefaults];
    [standardDefaults synchronize];
    
    [viewsForStatePreservation enumerateObjectsUsingBlock: ^(NSString * viewPropertyName, NSUInteger idx, BOOL *stop) {
        
        SEL selector = NSSelectorFromString(viewPropertyName);
        IMP imp = [self methodForSelector:selector];
        UIView * (*func)(id, SEL) = (void *)imp;
        UIView * view = func(self, selector);
        
        NSAssert(view,
                 @"Could not find a property with name '%@' on '%@",
                 view,
                 NSStringFromClass([self class]));
        
        NSNumber * alphaNum = [standardDefaults objectForKey: [NSString stringWithFormat:
                                                               @"%@%@",
                                                               standardDefaultsKeyViewStatePreservationAlpha,
                                                               viewPropertyName]];
        
        CGFloat newAlpha = 0.0;
        
        if (alphaNum)
        {
            newAlpha = [alphaNum floatValue];
        }
        
        [view setAlpha: newAlpha];
    }];
}

- (void) saveUIState
{
    NSUserDefaults * standardDefaults = [NSUserDefaults standardUserDefaults];
    
    [viewsForStatePreservation enumerateObjectsUsingBlock: ^(NSString * viewPropertyName, NSUInteger idx, BOOL *stop) {
        
        SEL selector = NSSelectorFromString(viewPropertyName);
        IMP imp = [self methodForSelector:selector];
        UIView * (*func)(id, SEL) = (void *)imp;
        UIView * view = func(self, selector);
        
        NSAssert(view,
                 @"Could not find a property with name '%@' on '%@",
                 view,
                 NSStringFromClass([self class]));
        
        [standardDefaults setObject: [NSNumber numberWithFloat: [view alpha]]
                             forKey: [NSString stringWithFormat:
                                      @"%@%@",
                                      standardDefaultsKeyViewStatePreservationAlpha,
                                      viewPropertyName]];
    }];
    
    [standardDefaults synchronize];
}

- (void) updateContentLayout
{
    CGRect viewBounds = [[self view] bounds];
    
    CGFloat numCellsPerRow = viewBounds.size.width / activityCellDim;
    
    CGFloat numRows = 0;
    
    if ([self harmonyConfiguration])
    {
        numRows = ceilf(([[[self harmonyConfiguration] activity] count] - 1) / numCellsPerRow);
    }

    CGFloat collectionViewHeight = numRows * activityCellDim;
    
    [[self activityCollectionViewHeightConstraint] setConstant: collectionViewHeight];
    
    [[self staticActivitiesViewHeightConstraint] setConstant: ([[self staticActivitiesView] alpha] == 0.0) ? 0.0 : activityCellDim];
}

- (void) updateUIForCurrentActivity: (FSCActivity *) currentActivity
{
    FSCControlGroup * volumeControlGroup = [currentActivity volumeControlGroup];
    FSCControlGroup * transportBasicControlGroup = [currentActivity transportBasicControlGroup];
    FSCControlGroup * transportExtendedControlGroup = [currentActivity transportExtendedControlGroup];
    
    BOOL powerOffActivityHidden = [[[currentActivity label] lowercaseString] isEqualToString: @"poweroff"];
    
    if (!powerOffActivityHidden)
    {
        FSCActivity * powerOffActivity = [[[self harmonyConfiguration] activity] lastObject];
        
        if ([[[powerOffActivity label] lowercaseString] isEqualToString: @"poweroff"])
        {
            [[self powerOffIconImageView] setImage: [powerOffActivity maskedImageWithColor: [self colorForActivityMask]]];
            [[self powerOffLabel] setText: [powerOffActivity label]];
        }
        else
        {
            powerOffActivityHidden = YES;
        }
    }
    
    [[self view] layoutIfNeeded];
    
    [UIView animateWithDuration: 0.5
                     animations: ^{
                         
                         [[self staticActivitiesView] setAlpha: (volumeControlGroup ||
                                                                 transportBasicControlGroup ||
                                                                 transportExtendedControlGroup ||
                                                                 !powerOffActivityHidden) ? 1.0 : 0.0];
                         [[self volumeView] setAlpha: volumeControlGroup ? 1.0 : 0.0];
                         [[self transportView] setAlpha: (transportBasicControlGroup || transportExtendedControlGroup) ? 1.0 : 0.0];
                         [[self powerOffView] setAlpha: powerOffActivityHidden ? 0.0 : 1.0];
                     }
     completion: ^(BOOL finished) {
         
         [UIView animateWithDuration: 0.5
                          animations: ^{
                              
                              [self updateContentLayout];
                              
                              [[self view] layoutIfNeeded];
                          }];
     }];
}

- (IBAction) powerOffTapped: (id) sender
{
    [[self statusLabel] setText: NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-POWERING_OFF", nil)];
    
    [self performBlockingClientActionsWithBlock:^(FSCHarmonyClient *client) {
        
        [client turnOff];
    }
                      mainThreadCompletionBlock: nil];
}

- (void) executeFunction: (FSCFunction * (^)(FSCActivity * currentActivity))functionBlock
{
    BOOL repeat = NO;
    
    [self executeFunction: functionBlock
                   repeat: &repeat];
}

- (void) executeFunction: (FSCFunction * (^)(FSCActivity * currentActivity))functionBlock
                  repeat: (BOOL *) repeat
{
    [self performBlockingClientActionsWithBlock: ^(FSCHarmonyClient *client) {
        
        FSCActivity * currentActivity = [client currentActivityFromConfiguration: [self harmonyConfiguration]];
        
        FSCFunction * function = functionBlock(currentActivity);
        
        if (function)
        {
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                [[self statusLabel] setText: [NSString stringWithFormat:
                                              @"%@...",
                                              [function label]]];
            });
            
            BOOL firstTime = YES;
            
            while (*repeat ||
                   firstTime)
            {
                firstTime = NO;
              
#ifdef STATIC_ACTIVITY
                DLog(@"Executing %@", [function label]);
                [NSThread sleepForTimeInterval: 1];
#else
                [client executeFunction: function
                               withType: FSCHarmonyClientFunctionTypePress];
                [client executeFunction: function
                               withType: FSCHarmonyClientFunctionTypeRelease];
#endif
            }
        }
    }
     mainThreadCompletionBlock: nil];
}

- (IBAction) volumeDownPressed: (id) sender
{
    repeatFunction = YES;
    
    [self executeFunction: ^FSCFunction *(FSCActivity *currentActivity) {
        
        return [[currentActivity volumeControlGroup] volumeDownFunction];
    }
     repeat: &repeatFunction];
}

- (IBAction) volumeUpPressed: (id) sender
{
    repeatFunction = YES;
    
    [self executeFunction: ^FSCFunction *(FSCActivity *currentActivity) {
        
        return [[currentActivity volumeControlGroup] volumeUpFunction];
    }
     repeat: &repeatFunction];
}

- (IBAction) volumeReleased: (id) sender
{
    repeatFunction = NO;
}

- (IBAction) playPauseTapped: (UIGestureRecognizer *) gesture
{
    [self executeFunction: ^FSCFunction *(FSCActivity *currentActivity) {
        
        FSCControlGroup * controlGroup = [currentActivity transportBasicControlGroup];
        
        FSCFunction * function = playToggle ? [controlGroup playFunction] : [controlGroup pauseFunction];
        
        playToggle = !playToggle;
        
        return function;
    }];
}

- (IBAction) backwardForwardLongPressed: (UILongPressGestureRecognizer *) gesture
{
    DLog(@"%@ state: %li; num taps required: %lu",
         NSStringFromSelector(_cmd),
         (long)[gesture state],
         (unsigned long)[gesture numberOfTapsRequired]);
    
    if ([gesture state] == UIGestureRecognizerStateBegan)
    {
        backwardForwardGestureInitialLocation = [gesture locationInView: [gesture view]];
        
        gestureHandled = NO;
    }
    else if ([gesture state] == UIGestureRecognizerStateChanged)
    {
        if (!gestureHandled)
        {
            CGPoint newLocation = [gesture locationInView: [gesture view]];
            
            CGFloat delta = backwardForwardGestureInitialLocation.x - newLocation.x;
            
            if (fabs(delta) >= backwardForwardGestureMinimumDelta)
            {
                gestureHandled = YES;
                repeatFunction = ([gesture numberOfTapsRequired] == 1);
                
                [self executeFunction: ^FSCFunction *(FSCActivity *currentActivity) {
             
                    FSCFunction * function = nil;
                    
                    if (delta < 0.0)
                    {
                        function = [[currentActivity transportExtendedControlGroup] skipForwardFunction];
                    }
                    else
                    {
                        function = [[currentActivity transportExtendedControlGroup] skipBackwardFunction];
                    }
                    
                    return function;
                }
                               repeat: &repeatFunction];
            }
        }
    }
    else if ([gesture state] == UIGestureRecognizerStateEnded ||
             [gesture state] == UIGestureRecognizerStateCancelled)
    {
        repeatFunction = NO;
        gestureHandled = NO;
    }
}

#pragma mark - UICollectionViewDelegate

- (void) collectionView:(UICollectionView *) collectionView
didSelectItemAtIndexPath: (NSIndexPath *) indexPath
{
    FSCActivity * activity = [self activities][[indexPath item]];
    
    [[self statusLabel] setText: [NSString stringWithFormat:
                                  NSLocalizedString(@"TODAYVIEWCONTROLLER-STATUS-STARTING", nil),
                                  [activity label]]];
    
    [super collectionView: collectionView
 didSelectItemAtIndexPath: indexPath];
}

@end
