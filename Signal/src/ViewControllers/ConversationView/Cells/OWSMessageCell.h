//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"
//#import "JSQMessagesCollectionViewCell+OWS.h"
//#import "OWSExpirableMessageView.h"
//#import "OWSMessageMediaAdapter.h"
//#import <JSQMessagesViewController/JSQMessagesCollectionViewCellOutgoing.h>

NS_ASSUME_NONNULL_BEGIN

//@class JSQMediaItem;
@class OWSExpirationTimerView;

// TODO: Move to source.
static const CGFloat OWSExpirableMessageViewTimerWidth = 10.0f;

@interface OWSMessageCell
    : ConversationViewCell
// <OWSExpirableMessageView>

@property (nonatomic, readonly) OWSExpirationTimerView *expirationTimerView;
@property (nonatomic, readonly) NSLayoutConstraint *expirationTimerViewWidthConstraint;

- (void)startExpirationTimerWithExpiresAtSeconds:(double)expiresAtSeconds
                          initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)stopExpirationTimer;

//@property (nonatomic, nullable) id<OWSMessageMediaAdapter> mediaAdapter;

@end

NS_ASSUME_NONNULL_END
