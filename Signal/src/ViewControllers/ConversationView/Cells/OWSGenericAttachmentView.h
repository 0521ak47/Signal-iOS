//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

//#import "OWSMessageEditing.h"
//#import "OWSMessageMediaAdapter.h"
//#import <JSQMessagesViewController/JSQMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface OWSGenericAttachmentView : UIView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream isIncoming:(BOOL)isIncoming;

- (void)createContentsForSize:(CGSize)viewSize;

+ (CGFloat)bubbleHeight;

@end

NS_ASSUME_NONNULL_END
