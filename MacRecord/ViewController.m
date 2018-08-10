//
//  ViewController.m
//  MacRecord
//
//  Created by 钟勇 on 2018/7/13.
//  Copyright © 2018年 钟勇. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic,strong)AVCaptureSession *captureSession;
@property (nonatomic,strong)AVAssetWriter * assetWriter;

@property (nonatomic,strong)AVAssetWriterInput *videoWriterInput;
@property (nonatomic,strong)AVAssetWriterInput *audioWriterInput;

@property (nonatomic,strong)AVCaptureVideoDataOutput * videoOutput;
@property (nonatomic,strong)AVCaptureAudioDataOutput * audioOutput;

@property (nonatomic ,strong)dispatch_queue_t audioOutputQueue;
@property (nonatomic, strong)dispatch_queue_t videoOutputQueue;
@property (nonatomic, strong)dispatch_queue_t writerQueue;

@property (nonatomic,assign)BOOL canWrite;
@property (nonatomic,assign)BOOL isCapture;
@property (nonatomic,assign)BOOL isSuspend;

@property (nonatomic,assign)CMTime lastVideo;
@property (nonatomic,assign)CMTime lastAudio;
@property (nonatomic,assign)CMTime timeOffset;

@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initOutputQueue];
    [self initCapture];
    [self addOutput];
    self.canWrite = YES;
    self.isCapture = YES;
    self.isSuspend = NO;
}

- (IBAction)startRecord:(id)sender {
    [self initWrite];
    [self.captureSession startRunning];
    
}
- (IBAction)pauseRecord:(id)sender {
    if (self.isCapture) {
        self.isCapture = NO;
        self.isSuspend = YES;
    }
}
- (IBAction)stopRecord:(id)sender {
    [self.captureSession stopRunning];
    [self finishRecording];
}
- (IBAction)resumeRecord:(id)sender {
    if (!self.isCapture) {
        self.isCapture = YES;
    }
    
}
-(void)initOutputQueue{
    self.audioOutputQueue = dispatch_queue_create("audioOutputQueue.com", NULL);
    self.videoOutputQueue = dispatch_queue_create("videoOutputQueue.com", NULL);
    self.writerQueue = dispatch_queue_create("writerQueue", NULL);
    
}
-(void)initCapture{
    self.captureSession = [[AVCaptureSession alloc]init];
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    
    AVCaptureScreenInput * screenInput = [[AVCaptureScreenInput alloc]initWithDisplayID:CGMainDisplayID()];
    screenInput.cropRect = [NSScreen mainScreen].frame;
    screenInput.minFrameDuration = CMTimeMake(1, 10);
    
//    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
//    AVCaptureDeviceInput *videoDeviceinput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    NSError *error = nil;
    AVCaptureDeviceInput * audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if (!audioInput) {
        return;
    }
    
    if ([self.captureSession canAddInput:screenInput]) {
        [self.captureSession addInput:screenInput];
    }
    if ([self.captureSession canAddInput:audioInput]) {
        [self.captureSession addInput:audioInput];
    }
    
}

-(void)addOutput{
    self.videoOutput = [[AVCaptureVideoDataOutput alloc]init];
    NSDictionary *videoSet = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],kCVPixelBufferPixelFormatTypeKey, nil];
    self.videoOutput.videoSettings = videoSet;
    [self.videoOutput setSampleBufferDelegate:self queue:self.videoOutputQueue];
    
    self.audioOutput = [[AVCaptureAudioDataOutput alloc]init];
    [self.audioOutput setSampleBufferDelegate:self queue:self.audioOutputQueue];
    
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];
    }
    if ([self.captureSession canAddOutput:self.audioOutput]) {
        [self.captureSession addOutput:self.audioOutput];
    }
    
}
-(void)initWrite{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = [paths objectAtIndex:0];
    NSString *recordPath = [documents stringByAppendingString:@"/record111"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:recordPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:recordPath withIntermediateDirectories: NO attributes:nil error:nil];
    }
    NSString *fileName = [recordPath stringByAppendingString:@"/tem.mov"];
    self.assetWriter = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:fileName] fileType:AVFileTypeQuickTimeMovie error:nil];
    
    CGSize outputSize = CGSizeMake(2880, 1800);
    NSInteger numPixels = outputSize.width * outputSize.height;
    CGFloat   bitsPerPixel = 1.0;
    NSInteger bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary * videoCpmpressionDic = @{AVVideoAverageBitRateKey:@(bitsPerSecond),
                                           AVVideoExpectedSourceFrameRateKey:@(10),
                                           AVVideoMaxKeyFrameIntervalKey : @(10),
                                           AVVideoProfileLevelKey : AVVideoProfileLevelH264BaselineAutoLevel };
    
    NSDictionary * videoCompressionSettings = @{ AVVideoCodecKey : AVVideoCodecTypeH264,
                                                 AVVideoWidthKey  : @(outputSize.width),
                                                 AVVideoHeightKey : @(outputSize.height),
                                                 AVVideoCompressionPropertiesKey : videoCpmpressionDic };
    
    if ([self.assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) {
        self.videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
        NSParameterAssert(self.videoWriterInput);
        self.videoWriterInput.expectsMediaDataInRealTime = YES;
        
    }
    if ([self.assetWriter canAddInput:self.videoWriterInput]) {
        [self.assetWriter addInput:self.videoWriterInput];
    }
    
    NSDictionary * audioSettings = @{  AVFormatIDKey:@(kAudioFormatMPEG4AAC) ,
                                       AVEncoderBitRatePerChannelKey:@(64000),
                                       AVSampleRateKey:@(44100.0),
                                       AVNumberOfChannelsKey:@(1)};
    if ([self.assetWriter canApplyOutputSettings:audioSettings forMediaType:AVMediaTypeAudio]) {
        self.audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
        NSParameterAssert(self.audioWriterInput);
        self.audioWriterInput.expectsMediaDataInRealTime = YES;
    }
    if ([self.assetWriter canAddInput:self.audioWriterInput]) {
        [self.assetWriter addInput:self.audioWriterInput];
    }
    
}

#pragma mark - dataOutputDelegete
-(void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    if (connection == [self.videoOutput connectionWithMediaType:AVMediaTypeVideo] ) {
        [self appendVideoSampleBuffer:sampleBuffer];
    }
    else if(connection == [self.audioOutput connectionWithMediaType:AVMediaTypeAudio]){
        [self appendAudioSampleBuffer:sampleBuffer];
    }
}

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self appendSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeVideo];
}

- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self appendSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeAudio];
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer ofMediaType:(NSString *)mediaType{
    if (sampleBuffer == NULL) {
        return;
    }
    __block CMSampleBufferRef currentBuffer;
    CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &currentBuffer);
    dispatch_async(self.writerQueue, ^{
        NSParameterAssert(currentBuffer);
        if (!self.isCapture) {
            return;
        }
        //计算暂停的时间
        if (self.isSuspend) {
            if (mediaType == AVMediaTypeVideo) {
                return;
            }
            self.isSuspend = NO;
            CMTime pts = CMSampleBufferGetPresentationTimeStamp(currentBuffer);
            CMTime last = self.lastAudio;
            if (last.flags & kCMTimeFlags_Valid) {
                self.timeOffset = CMTimeSubtract(pts, last);
            }
            self->_lastAudio.flags = 0;
            self->_lastVideo.flags = 0;
        }
        
        CFRetain(currentBuffer);
        if (self.timeOffset.value > 0) {
            currentBuffer = [self adjustTime:currentBuffer by:self.timeOffset];
        }
        
        //记录暂停前的时间
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(currentBuffer);
        CMTime dur = CMSampleBufferGetDuration(currentBuffer);
        if (dur.value > 0) {
            pts = CMTimeAdd(pts, dur);
        }
        if (mediaType == AVMediaTypeVideo) {
            self->_lastVideo = pts;
        }else {
            self->_lastAudio = pts;
        }
        
        if (self.canWrite && mediaType == AVMediaTypeVideo) {
            CMTime pts = CMSampleBufferGetPresentationTimeStamp(currentBuffer);
            /*
             pts的second 约等于 [[NSProcessInfo processInfo] systemUptime];
             
             */
            if (pts.value > 0) {
                self.canWrite = NO;
                [self.assetWriter startWriting];
                [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(currentBuffer)];
                
            }
            
        }
        
        AVAssetWriterInput * input = (mediaType == AVMediaTypeVideo )? self.videoWriterInput:self.audioWriterInput;
        if (input.readyForMoreMediaData) {
            BOOL success = [input appendSampleBuffer:currentBuffer];
            if (!success) {
                NSError *error = self.assetWriter.error;
                NSLog(@"input failure with error %@:",error);
            }
        }else{
            
            NSLog( @"%@ input not ready for more media data, dropping buffer", mediaType );
        }
        
        CFRelease(currentBuffer);
    });

}

-(void)finishRecording{
    if (self.assetWriter && self.assetWriter.status == AVAssetWriterStatusWriting) {
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSError * error = self.assetWriter.error;
            if(error){
                
                NSLog(@"AssetWriterFinishError:%@",error);
            }else{
                self.canWrite = YES;
                NSLog(@"成功!");
            }
            self.assetWriter = nil;
        }];
    }
}
//调整媒体数据的时间
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset {
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo* pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    return sout;
}


@end
