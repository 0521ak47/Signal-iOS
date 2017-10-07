//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSGenericAttachmentView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import "AttachmentSharing.h"

//#import "OWSExpirationTimerView.h"
//#import "UIView+OWS.h"
//#import <JSQMessagesViewController/JSQMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell ()

@property (nonatomic) OWSMessageCellType cellType;

@property (nonatomic, nullable) NSString *textMessage;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) TSAttachmentPointer *attachmentPointer;
@property (nonatomic) CGSize contentSize;

// The text label is used so frequently that we always keep one around.
@property (nonatomic) UILabel *textLabel;
@property (nonatomic, nullable) UIImageView *bubbleImageView;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic, nullable) UIImageView *stillImageView;
@property (nonatomic, nullable) YYAnimatedImageView *animatedImageView;
@property (nonatomic, nullable) UIView *customView;
@property (nonatomic, nullable) AttachmentPointerView *attachmentPointerView;
@property (nonatomic, nullable) OWSGenericAttachmentView *attachmentView;
@property (nonatomic, nullable) OWSAudioMessageView *audioMessageView;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *contentConstraints;

//@property (strong, nonatomic) IBOutlet OWSExpirationTimerView *expirationTimerView;
//@property (strong, nonatomic) IBOutlet NSLayoutConstraint *expirationTimerViewWidthConstraint;

@end

@implementation OWSMessageCell

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }
    
    return self;
}

- (void)commontInit
{
    OWSAssert(!self.textLabel);
    
//    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
    self.layoutMargins = UIEdgeInsetsZero;
    
    self.contentView.backgroundColor = [UIColor whiteColor];

    self.bubbleImageView = [UIImageView new];
    self.bubbleImageView.layoutMargins = UIEdgeInsetsZero;
    self.bubbleImageView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.bubbleImageView];
    [self.bubbleImageView autoPinToSuperviewEdges];

    self.textLabel = [UILabel new];
    self.textLabel.font = [UIFont ows_regularFontWithSize:16.f];
    self.textLabel.numberOfLines = 0;
    self.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    [self.bubbleImageView addSubview:self.textLabel];
    OWSAssert(self.textLabel.superview);

    // Hide these views by default.
    self.bubbleImageView.hidden = YES;
    self.textLabel.hidden = YES;

    UITapGestureRecognizer *tap =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
    [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self addGestureRecognizer:longPress];
}

- (NSCache *)displayableTextCache
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        // Cache the results for up to 1,000 messages.
        cache.countLimit = 1000;
    });
    return cache;
}

- (NSString *)displayableTextForText:(NSString *)text
                       interactionId:(NSString *)interactionId
{
    OWSAssert(text);
    OWSAssert(interactionId.length > 0);
    
    NSString *_Nullable displayableText = [[self displayableTextCache] objectForKey:interactionId];
    if (!displayableText) {
        // Only show up to 2kb of text.
        const NSUInteger kMaxTextDisplayLength = 2 * 1024;
        displayableText = [[DisplayableTextFilter new] displayableText:text];
        if (displayableText.length > kMaxTextDisplayLength) {
            // Trim whitespace before _AND_ after slicing the snipper from the string.
            NSString *snippet = [[[displayableText
                                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                  substringWithRange:NSMakeRange(0, kMaxTextDisplayLength)]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            displayableText =
            [NSString stringWithFormat:NSLocalizedString(@"OVERSIZE_TEXT_DISPLAY_FORMAT",
                                                         @"A display format for oversize text messages."),
             snippet];
        }
        if (!displayableText) {
            displayableText = @"";
        }
        [[self displayableTextCache] setObject:displayableText forKey:interactionId];
    }
    return displayableText;
}

- (NSString *)displayableTextForAttachmentStream:(TSAttachmentStream *)attachmentStream
                       interactionId:(NSString *)interactionId
{
    OWSAssert(attachmentStream);
    OWSAssert(interactionId.length > 0);
    
    NSString *_Nullable displayableText = [[self displayableTextCache] objectForKey:interactionId];
    if (displayableText) {
        return displayableText;
    }
    
    NSData *textData = [NSData dataWithContentsOfURL:attachmentStream.mediaURL];
    NSString *text = [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
    return [self displayableTextForText:text
                          interactionId:interactionId];
}

- (void)ensureCellType
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    
    TSMessage *interaction = (TSMessage *) self.viewItem.interaction;
    if (interaction.body.length > 0) {
        self.cellType = OWSMessageCellType_TextMessage;
        // TODO: This can be expensive.  Should we cache it on the view item?
        self.textMessage = [self displayableTextForText:interaction.body
                                          interactionId:interaction.uniqueId];
        return;
    } else {
        NSString *_Nullable attachmentId = interaction.attachmentIds.firstObject;
        if (attachmentId.length > 0) {
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
            if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                self.attachmentStream = (TSAttachmentStream *)attachment;
                
                if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                    self.cellType = OWSMessageCellType_OversizeTextMessage;
                    // TODO: This can be expensive.  Should we cache it on the view item?
                    self.textMessage = [self displayableTextForAttachmentStream:self.attachmentStream
                                                                  interactionId:interaction.uniqueId];
                    return;
                } else if ([self.attachmentStream isAnimated] ||
                           [self.attachmentStream isImage] ||
                           [self.attachmentStream isVideo]) {
                    if ([self.attachmentStream isAnimated]) {
                        self.cellType = OWSMessageCellType_AnimatedImage;
                    } else if ([self.attachmentStream isImage]) {
                        self.cellType = OWSMessageCellType_StillImage;
                    } else if ([self.attachmentStream isVideo]) {
                        self.cellType = OWSMessageCellType_Video;
                    } else {
                        OWSFail(@"%@ unexpected attachment type.", self.logTag);
                        self.cellType = OWSMessageCellType_GenericAttachment;
                        return;
                    }
                    self.contentSize = [self.attachmentStream imageSizeWithoutTransaction];
                    if (self.contentSize.width <= 0 ||
                        self.contentSize.height <= 0) {
                        self.cellType = OWSMessageCellType_GenericAttachment;
                    }
                    return;
                } else if ([self.attachmentStream isAudio]) {
                    self.cellType = OWSMessageCellType_Audio;
                    return;
                } else {
                    self.cellType = OWSMessageCellType_GenericAttachment;
                    return;
//                    break;
//                } else if ([self.attachmentStream isVideo] || [self.attachmentStream isAudio]) {
//                    adapter.mediaItem = [[TSVideoAttachmentAdapter alloc]
//                                         initWithAttachment:stream
//                                         incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
//                    adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
//                    break;
//                } else {
//                    adapter.mediaItem = [[TSGenericAttachmentAdapter alloc]
//                                         initWithAttachment:stream
//                                         incoming:[interaction isKindOfClass:[TSIncomingMessage class]]];
//                    adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;
//                    break;
                }
            } else if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                self.cellType = OWSMessageCellType_DownloadingAttachment;
                self.attachmentPointer = (TSAttachmentPointer *)attachment;
//                adapter.mediaItem =
//                [[AttachmentPointerAdapter alloc] initWithAttachmentPointer:pointer
//                                                                 isIncoming:isIncomingAttachment];
                return;
            }
//            } else {
        }
    }

    // TODO:
    //                    adapter.mediaItem.appliesMediaViewMaskAsOutgoing = !isIncomingAttachment;

    self.cellType = OWSMessageCellType_Unknown;
}

- (void)loadForDisplay
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    
    [self ensureCellType];
    
    BOOL isIncoming = self.isIncoming;
    JSQMessagesBubbleImage *bubbleImageData = isIncoming ? [self.bubbleFactory incoming] : [self.bubbleFactory outgoing];
    self.bubbleImageView.image = bubbleImageData.messageBubbleImage;

    switch(self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [self loadForTextDisplay];
            break;
        case OWSMessageCellType_StillImage:
            [self loadForStillImageDisplay];
            break;
        case OWSMessageCellType_AnimatedImage:
            [self loadForAnimatedImageDisplay];
            break;
        case OWSMessageCellType_Audio:
            [self loadForAudioDisplay];
            break;
        case OWSMessageCellType_Video:
            [self loadForVideoDisplay];
            break;
        case OWSMessageCellType_GenericAttachment: {
            self.attachmentView = [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream
                                                                                                 isIncoming:self.isIncoming];
            [self.attachmentView createContentsForSize:self.bounds.size];
            [self replaceBubbleWithView:self.attachmentView];
            [self addAttachmentUploadViewIfNecessary:self.attachmentView];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            [self loadForDownloadingAttachment];
            break;
        }
    }

    // If we have an outgoing attachment and we haven't created a
    // AttachmentUploadView yet, do so now.
    //
    // For some attachment types, we may create this view earlier
    // so that we can take advantage of its callback.
//    if (self.attachmentStream &&
//        !self.isIncoming &&
//        !self.attachmentUploadView) {
//        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
//                                                                           superview:imageView
//                                                             attachmentStateCallback:^(BOOL isAttachmentReady) {
//                                                             }];
//    }

//    [self.textLabel addBorderWithColor:[UIColor blueColor]];
//    [self.bubbleImageView addBorderWithColor:[UIColor greenColor]];

//    dispatch_async(dispatch_get_main_queue(), ^{
//        NSLog(@"---- %@", self.viewItem.interaction.debugDescription);
//        NSLog(@"cell: %@", NSStringFromCGRect(self.frame));
//        NSLog(@"contentView: %@", NSStringFromCGRect(self.contentView.frame));
//        NSLog(@"textLabel: %@", NSStringFromCGRect(self.textLabel.frame));
//        NSLog(@"bubbleImageView: %@", NSStringFromCGRect(self.bubbleImageView.frame));
//    });
}

- (void)loadForTextDisplay {
    self.bubbleImageView.hidden = NO;
    self.textLabel.hidden = NO;
    self.textLabel.text = self.textMessage;
    self.textLabel.textColor = [self textColor];
    
    self.contentConstraints = @[
                                [self.textLabel autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
                                [self.textLabel autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
                                [self.textLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],
                                [self.textLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
                                ];
}

- (void)loadForStillImageDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isImage]);
    
    UIImage *_Nullable image = self.attachmentStream.image;
    if (!image) {
        DDLogError(@"%@ Could not load image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }
    
    self.stillImageView = [[UIImageView alloc] initWithImage:image];
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self replaceBubbleWithView:self.stillImageView];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView];
}

- (void)loadForAnimatedImageDisplay {
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAnimated]);
    
    NSString *_Nullable filePath = [self.attachmentStream filePath];
    YYImage *_Nullable animatedImage = nil;
    if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
        animatedImage = [YYImage imageWithContentsOfFile:filePath];
    }
    if (!animatedImage) {
        DDLogError(@"%@ Could not load animated image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }
    
    self.animatedImageView = [[YYAnimatedImageView alloc] init];
    self.animatedImageView.image = animatedImage;
    [self replaceBubbleWithView:self.animatedImageView];
    [self addAttachmentUploadViewIfNecessary:self.animatedImageView];
}

- (void)loadForAudioDisplay {
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAudio]);
    
    self.audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:self.attachmentStream
                                                                 isIncoming:self.isIncoming
                                                                   viewItem:self.viewItem];
    self.viewItem.lastAudioMessageView = self.audioMessageView;
    [self.audioMessageView createContentsForSize:self.bounds.size];
    [self replaceBubbleWithView:self.audioMessageView];
    [self addAttachmentUploadViewIfNecessary:self.audioMessageView];
}

- (void)loadForVideoDisplay {
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isVideo]);

//    CGSize size = [self mediaViewDisplaySize];
    
    UIImage *_Nullable image = self.attachmentStream.image;
    if (!image) {
        DDLogError(@"%@ Could not load image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }
    
    self.stillImageView = [[UIImageView alloc] initWithImage:image];
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self replaceBubbleWithView:self.stillImageView];

    UIImage *videoPlayIcon = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:videoPlayIcon];
    [self.stillImageView addSubview:videoPlayButton];
    [videoPlayButton autoCenterInSuperview];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                         videoPlayButton.hidden = !isAttachmentReady;
                     }];
}

- (void)loadForDownloadingAttachment {
    OWSAssert(self.attachmentPointer);
    
    self.customView = [UIView new];
    switch (self.attachmentPointer.state) {
        case TSAttachmentPointerStateEnqueued:
            self.customView.backgroundColor = (self.isIncoming
                                               ? [UIColor jsq_messageBubbleLightGrayColor]
                                               : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateDownloading:
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(attachmentDownloadProgress:)
                                                         name:kAttachmentDownloadProgressNotification
                                                       object:nil];
            self.customView.backgroundColor = (self.isIncoming
                                               ? [UIColor jsq_messageBubbleLightGrayColor]
                                               : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateFailed:
            self.customView.backgroundColor = [UIColor grayColor];
            break;
    }
    [self replaceBubbleWithView:self.customView];
    
    self.attachmentPointerView = [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer
                                                                               isIncoming:self.isIncoming];
    [self.customView addSubview:self.attachmentPointerView];
    [self.attachmentPointerView autoPinWidthToSuperviewWithMargin:20.f];
    [self.attachmentPointerView autoVCenterInSuperview];
}

- (void)replaceBubbleWithView:(UIView *)view {
    OWSAssert(view);
    
    view.userInteractionEnabled = NO;
    [self.contentView addSubview:view];
    self.contentConstraints = [view autoPinToSuperviewEdges];
    [self cropViewToBubbbleShape:view];
}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView {
    [self addAttachmentUploadViewIfNecessary:attachmentView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                     }];
}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView
                   attachmentStateCallback:(AttachmentStateBlock)attachmentStateCallback
{
    OWSAssert(attachmentView);
    OWSAssert(attachmentStateCallback);
    
    if (!self.isIncoming) {
        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                                                           superview:attachmentView
                                                             attachmentStateCallback:attachmentStateCallback];
    }
}

- (void)cropViewToBubbbleShape:(UIView *)view
{
//    OWSAssert(CGRectEqualToRect(self.bounds, self.contentView.frame));
//    DDLogError(@"cropViewToBubbbleShape: %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description);
//    DDLogError(@"\t %@ %@ %@ %@",
//               NSStringFromCGRect(self.frame),
//               NSStringFromCGRect(self.contentView.frame),
//               NSStringFromCGRect(view.frame),
//               NSStringFromCGRect(view.superview.bounds));

//    view.frame = view.superview.bounds;
    view.frame = self.bounds;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:view
                                                                isOutgoing:!self.isIncoming];
}

//// TODO:
//- (void)setFrame:(CGRect)frame {
//    [super setFrame:frame];
//
//    DDLogError(@"setFrame: %@ %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description, NSStringFromCGRect(frame));
//}
//
//// TODO:
//- (void)setBounds:(CGRect)bounds {
//    [super setBounds:bounds];
//
//    DDLogError(@"setBounds: %@ %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description, NSStringFromCGRect(bounds));
//}

- (void)showAttachmentErrorView
{
    // TODO: We could do a better job of indicating that the image could not be loaded.
    self.customView = [UIView new];
    self.customView.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
    self.customView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.customView];
    self.contentConstraints = [self.customView autoPinToSuperviewEdges];
    [self cropViewToBubbbleShape:self.customView];
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth
               maxMessageWidth:(int)maxMessageWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    
    [self ensureCellType];

    switch(self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            BOOL isRTL = self.isRTL;
            CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
            CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;
            CGFloat textVMargin = self.textVMargin;
            CGFloat maxTextWidth = maxMessageWidth - (leftMargin + rightMargin);
            
            self.textLabel.text = self.textMessage;
            CGSize textSize = [self.textLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
            CGSize result = CGSizeMake((CGFloat) ceil(textSize.width + leftMargin + rightMargin),
                                       (CGFloat) ceil(textSize.height + textVMargin * 2));
            //        NSLog(@"???? %@", self.viewItem.interaction.debugDescription);
            //        NSLog(@"\t %@", messageBody);
            //        NSLog(@"textSize: %@", NSStringFromCGSize(textSize));
            //        NSLog(@"result: %@", NSStringFromCGSize(result));
            return result;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Video:
        {
            OWSAssert(self.contentSize.width > 0);
            OWSAssert(self.contentSize.height > 0);
            
            // TODO: Adjust this behavior.
            const CGFloat maxContentWidth = maxMessageWidth;
            const CGFloat maxContentHeight = maxMessageWidth;
            CGFloat contentWidth = (CGFloat) round(maxContentWidth);
            CGFloat contentHeight = (CGFloat) round(maxContentWidth * self.contentSize.height / self.contentSize.width);
            if (contentHeight > maxContentHeight) {
                contentWidth = (CGFloat) round(maxContentHeight * self.contentSize.width / self.contentSize.height);
                contentHeight = (CGFloat) round(maxContentHeight);
            }
            CGSize result = CGSizeMake(contentWidth, contentHeight);
//            DDLogError(@"measuring: %@ %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description, self.attachmentStream.contentType);
//            DDLogError(@"\t contentSize: %@", NSStringFromCGSize(self.contentSize));
//            DDLogError(@"\t result: %@", NSStringFromCGSize(result));
            return result;
        }
        case OWSMessageCellType_Audio:
            return CGSizeMake(maxMessageWidth, self.audioBubbleHeight);
        case OWSMessageCellType_GenericAttachment:
            return CGSizeMake(maxMessageWidth, [OWSGenericAttachmentView bubbleHeight]);
        case OWSMessageCellType_DownloadingAttachment:
            return CGSizeMake(200, 90);
    }
    
    return CGSizeMake(maxMessageWidth, maxMessageWidth);
}

- (BOOL)isIncoming {
    return YES;
}

- (CGFloat)textLeadingMargin {
    return self.isIncoming ? 15 : 10;
}

- (CGFloat)textTrailingMargin {
    return self.isIncoming ? 10 : 15;
}

- (CGFloat)textVMargin {
    return 10;
}

- (UIColor *)textColor {
    return self.isIncoming ? [UIColor blackColor] : [UIColor whiteColor];
}

- (CGFloat)audioIconHMargin
{
    return 12.f;
}

- (CGFloat)audioIconHSpacing
{
    return 10.f;
}

- (CGFloat)audioIconVMargin
{
    return 12.f;
}

- (CGFloat)audioBubbleHeight
{
    return self.audioIconSize + self.audioIconVMargin * 2;
}

- (CGFloat)audioIconSize
{
    return 40.f;
}

//- (UIColor *)audioTextColor
//{
//    return (self.incoming ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor whiteColor]);
//}
//
//- (UIColor *)audioColorWithOpacity:(CGFloat)alpha
//{
//    return [self.audioTextColor blendWithColor:self.bubbleBackgroundColor alpha:alpha];
//}

- (OWSMessagesBubbleImageFactory *)bubbleFactory
{
    static OWSMessagesBubbleImageFactory *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [OWSMessagesBubbleImageFactory new];
    });
    return instance;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSLayoutConstraint deactivateConstraints:self.contentConstraints];
    self.contentConstraints = nil;

    self.textMessage = nil;
    self.attachmentStream = nil;
    self.attachmentPointer = nil;
    self.contentSize = CGSizeZero;
    
    // The text label is used so frequently that we always keep one around.
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
    self.bubbleImageView.image = nil;
    self.bubbleImageView.hidden = YES;
    
    [self.stillImageView removeFromSuperview];
    self.stillImageView = nil;
    [self.animatedImageView removeFromSuperview];
    self.animatedImageView = nil;
    [self.customView removeFromSuperview];
    self.customView = nil;
    [self.attachmentPointerView removeFromSuperview];
    self.attachmentPointerView = nil;
    [self.attachmentView removeFromSuperview];
    self.attachmentView = nil;
    [self.audioMessageView removeFromSuperview];
    self.audioMessageView = nil;
    self.attachmentUploadView = nil;
    self.cellType = OWSMessageCellType_Unknown;
}

//- (void)awakeFromNib
//{
//    [super awakeFromNib];
//    self.expirationTimerViewWidthConstraint.constant = 0.0;
//
//    // Our text alignment needs to adapt to RTL.
//    self.cellBottomLabel.textAlignment = [self.cellBottomLabel textAlignmentUnnatural];
//}
//
//- (void)prepareForReuse
//{
//    [super prepareForReuse];
//    self.mediaView.alpha = 1.0;
//    self.expirationTimerViewWidthConstraint.constant = 0.0f;
//
//    [self.mediaAdapter setCellVisible:NO];
//
//    // Clear this adapter's views IFF this was the last cell to use this adapter.
//    [self.mediaAdapter clearCachedMediaViewsIfLastPresentingCell:self];
//    [_mediaAdapter setLastPresentingCell:nil];
//
//    self.mediaAdapter = nil;
//}
//
//- (void)setMediaAdapter:(nullable id<OWSMessageMediaAdapter>)mediaAdapter
//{
//    _mediaAdapter = mediaAdapter;
//
//    // Mark this as the last cell to use this adapter.
//    [_mediaAdapter setLastPresentingCell:self];
//}
//
//// pragma mark - OWSMessageCollectionViewCell
//
//- (void)setCellVisible:(BOOL)isVisible
//{
//    [self.mediaAdapter setCellVisible:isVisible];
//}
//
//- (UIColor *)ows_textColor
//{
//    return [UIColor whiteColor];
//}
//
//// pragma mark - OWSExpirableMessageView
//
//- (void)startExpirationTimerWithExpiresAtSeconds:(double)expiresAtSeconds
//                          initialDurationSeconds:(uint32_t)initialDurationSeconds
//{
//    self.expirationTimerViewWidthConstraint.constant = OWSExpirableMessageViewTimerWidth;
//    [self.expirationTimerView startTimerWithExpiresAtSeconds:expiresAtSeconds
//                                      initialDurationSeconds:initialDurationSeconds];
//}
//
//- (void)stopExpirationTimer
//{
//    [self.expirationTimerView stopTimer];
//}

#pragma mark - Notifications:

// TODO: Move this logic into AttachmentPointerView.
- (void)attachmentDownloadProgress:(NSNotification *)notification
{
    NSNumber *progress = notification.userInfo[kAttachmentDownloadProgressKey];
    NSString *attachmentId = notification.userInfo[kAttachmentDownloadAttachmentIDKey];
    if (!self.attachmentPointer ||
        ![self.attachmentPointer.uniqueId isEqualToString:attachmentId]) {
        OWSFail(@"%@ Unexpected attachment progress notification: %@", self.logTag, attachmentId);
        return;
    }
    self.attachmentPointerView.progress = progress.floatValue;
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);
    
    if (sender.state == UIGestureRecognizerStateRecognized) {
        
        if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
            if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
                return;
            } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
                // Ignore taps on outgoing messages being sent.
                return;
            }
        }
        
        switch(self.cellType) {
            case OWSMessageCellType_TextMessage:
                break;
            case OWSMessageCellType_OversizeTextMessage:
                [self.delegate didTapOversizeTextMessage:self.textMessage
                                        attachmentStream:self.attachmentStream];
                break;
            case OWSMessageCellType_StillImage:
                [self.delegate didTapImageViewItem:self.viewItem
                                  attachmentStream:self.attachmentStream
                                         imageView:self.stillImageView];
                break;
            case OWSMessageCellType_AnimatedImage:
                [self.delegate didTapImageViewItem:self.viewItem
                                  attachmentStream:self.attachmentStream
                                         imageView:self.animatedImageView];
                break;
            case OWSMessageCellType_Audio:
                [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:self.attachmentStream];
                return;
            case OWSMessageCellType_Video:
                [self.delegate didTapVideoViewItem:self.viewItem attachmentStream:self.attachmentStream];
                return;
            case OWSMessageCellType_GenericAttachment:
                [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
//                [self.delegate didTapGenericAttachment:self.viewItem attachmentStream:self.attachmentStream];
                break;
            case OWSMessageCellType_DownloadingAttachment: {
                OWSAssert(self.attachmentPointer);
                if (self.attachmentPointer.state == TSAttachmentPointerStateFailed) {
                    [self.delegate didTapFailedIncomingAttachment:self.viewItem attachmentPointer:self.attachmentPointer];
                }
                break;
            }
        }
        
        [self.delegate didTapViewItem:self.viewItem cellType:self.cellType];
    }
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);
    
    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
//        [self.delegate didLongPressViewItem:self.viewItem cellType:self.cellType];
        
        CGPoint location = [sender locationInView:self];
        [self showMenuController:location];
    }
}

#pragma mark - UIMenuController

- (void)showMenuController:(CGPoint)fromLocation
{
    [self becomeFirstResponder];
    
    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO
                                                       animated:NO];
    }
    
    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    //
    // TODO: Should we offer "save" as well?
    NSArray *menuItems = @[
                           [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                                                               @"Short name for edit menu item to share contents of media message.")
                                                      action:self.shareActionSelector],
                           [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_MESSAGE_METADATA_ACTION",
                                                                               @"Short name for edit menu item to show message metadata.")
                                                      action:self.metadataActionSelector],
                           [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_COPY_ACTION", @"Short name for edit menu item to copy contents of media message.")
                                                      action:self.copyActionSelector],
//                           [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
//                                                                               @"Short name for edit menu item to save contents of media message.")
//                                                      action:self.saveActionSelector],
                           [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_DELETE_ACTION", @"Short name for edit menu item to delete contents of media message.")
                                                      action:self.deleteActionSelector],
                           ];
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x,
                                   fromLocation.y,
                                   1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect
                                                    inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES
                                                   animated:YES];
}

- (SEL)copyActionSelector
{
    return NSSelectorFromString(@"copyAction:");
}

//- (SEL)saveActionSelector
//{
//    return NSSelectorFromString(@"save:");
//}

- (SEL)shareActionSelector
{
    return NSSelectorFromString(@"shareAction:");
}

- (SEL)deleteActionSelector
{
    return NSSelectorFromString(@"deleteAction:");
}

- (SEL)metadataActionSelector
{
    return NSSelectorFromString(@"metadataAction:");
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

// We only use custom actions in UIMenuController.
- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    DDLogVerbose(@"%@ canPerformAction: %@", self.logTag, NSStringFromSelector(action));

    if (action == self.copyActionSelector) {
        return [self hasActionContent];
//    } else if (action == self.saveActionSelector) {
//        return YES;
    } else if (action == self.shareActionSelector) {
        return [self hasActionContent];
    } else if (action == self.deleteActionSelector) {
        return YES;
    } else if (action == self.metadataActionSelector) {
        return YES;
    } else {
        return NO;
    }
}

- (void)copyAction:(nullable id)sender
{
    switch(self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [UIPasteboard.generalPasteboard setString:self.textMessage];
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment: {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachmentStream.contentType];
            if (!utiType) {
                OWSFail(@"%@ Unknown MIME type: %@", self.logTag, self.attachmentStream.contentType);
                utiType = (NSString *)kUTTypeGIF;
            }
            NSData *data = [NSData dataWithContentsOfURL:[self.attachmentStream mediaURL]];
            if (!data) {
                OWSFail(@"%@ Could not load attachment data: %@", self.logTag, [self.attachmentStream mediaURL]);
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't copy not-yet-downloaded attachment", self.logTag);
            break;
        }
    }
}

- (void)shareAction:(nullable id)sender
{
    switch(self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [AttachmentSharing showShareUIForText:self.textMessage];
            break;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSFail(@"%@ Can't share not-yet-downloaded attachment", self.logTag);
            break;
        }
    }
}

- (void)deleteAction:(nullable id)sender
{
    [self.viewItem.interaction remove];
}

- (void)metadataAction:(nullable id)sender
{
    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    [self.delegate showMetadataViewForMessage:message];
}

- (BOOL)hasActionContent
{
    switch(self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return self.textMessage.length > 0;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
        case OWSMessageCellType_GenericAttachment:
            return self.attachmentStream != nil;
        case OWSMessageCellType_DownloadingAttachment: {
            return NO;
        }
    }
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
