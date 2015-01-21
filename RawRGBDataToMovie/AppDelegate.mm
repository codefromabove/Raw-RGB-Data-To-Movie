//
//  AppDelegate.m
//  RawRGBDataToMovie
//
//  Created by Philip Schneider on 1/21/15.
//  Copyright (c) 2015 Code From Above, LLC. All rights reserved.
//

#import "AppDelegate.h"

#import <AVFoundation/AVFoundation.h>


#define VID_WIDTH  512
#define VID_HEIGHT 256
#define USE_KEY_VALUE_OBSERVATION 0

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow                      *window;
@property (nonatomic, strong) NSSavePanel               *savePanel;

@property (strong) NSURL                                *writeURL;
@property (strong) AVAssetWriter                        *assetWriter;
@property (strong) AVAssetWriterInput                   *assetInput;
@property (strong) AVAssetWriterInputPixelBufferAdaptor *assetInputAdaptor;

#if USE_KEY_VALUE_OBSERVATION
@property          BOOL                                  isWaitingForInputReady;
@property (strong) dispatch_semaphore_t                  writeSemaphore;
#endif // USE_KEY_VALUE_OBSERVATION

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

#if USE_KEY_VALUE_OBSERVATION

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"readyForMoreMediaData"])
    {
        if (_isWaitingForInputReady && _assetInput.isReadyForMoreMediaData)
        {
            _isWaitingForInputReady = NO;
            dispatch_semaphore_signal(_writeSemaphore);
        }
    }
}

#endif // USE_KEY_VALUE_OBSERVATION


static void ReleaseCVPixelBufferForCVPixelBufferCreateWithBytes(void *releaseRefCon, const void *baseAddr)
{
    CFDataRef bufferData = (CFDataRef)releaseRefCon;
    CFRelease(bufferData);
}

- (IBAction)testVideo:(id)sender
{
    //
    // Get location to save the movie
    //
    if (!_savePanel)
    {
        NSArray *fileTypesArray = [NSArray arrayWithObjects:@"mov", nil];

        _savePanel = [NSSavePanel savePanel];
        [_savePanel setAllowedFileTypes:fileTypesArray];
    }

    if ([_savePanel runModal] == NSFileHandlingPanelOKButton)
    {
        _writeURL = [_savePanel URL];
        NSLog(@"Selected file: %@", _writeURL);
    }
    else
        return;

    //
    // The asset writer fails if the file already exists...
    //
    NSError *removeError;
    BOOL     result = [[NSFileManager defaultManager] removeItemAtPath:[_writeURL path] error:&removeError];
    if (!result)
    {
        if (removeError.code != NSFileNoSuchFileError)
        {
            NSLog(@"%@", removeError);
            return;
        }
    }

#if USE_KEY_VALUE_OBSERVATION
    //
    // Set up for handling asynchrony
    //
    _isWaitingForInputReady = NO;
    _writeSemaphore         = dispatch_semaphore_create(0);
#endif // USE_KEY_VALUE_OBSERVATION



#define VID_USE_QUICKTIME_MOVIE 0

#if VID_USE_QUICKTIME_MOVIE
    NSDictionary *outputSettings = @{
                                     AVVideoCodecKey :AVVideoCodecAppleProRes4444,
                                     AVVideoWidthKey :@(VID_WIDTH),
                                     AVVideoHeightKey:@(VID_HEIGHT)
                                     };
#else

#if 1
    NSDictionary *outputSettings = @{
                                     AVVideoCodecKey :AVVideoCodecH264,
                                     AVVideoWidthKey :[NSNumber numberWithInt:VID_WIDTH],
                                     AVVideoHeightKey:[NSNumber numberWithInt:VID_HEIGHT],
                                     AVVideoCompressionPropertiesKey:@{
                                             AVVideoAverageBitRateKey:[NSNumber numberWithInt:(VID_WIDTH * VID_HEIGHT * 24)],
                                             AVVideoMaxKeyFrameIntervalKey:@(150),
                                             AVVideoProfileLevelKey:AVVideoProfileLevelH264BaselineAutoLevel,
                                             AVVideoAllowFrameReorderingKey:@NO,
                                             AVVideoH264EntropyModeKey:AVVideoH264EntropyModeCAVLC,
                                             AVVideoExpectedSourceFrameRateKey:@(30),
                                             }
                                     };
#else
    NSDictionary *outputSettings = @{
                                     AVVideoCodecKey :AVVideoCodecJPEG,
                                     AVVideoWidthKey :@(VID_WIDTH),
                                     AVVideoHeightKey:@(VID_HEIGHT)
                                     };
#endif
#endif // VID_USE_QUICKTIME_MOVIE

    _assetInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                     outputSettings:outputSettings];
    NSAssert(_assetInput, @"Cannot create asset input");

#if USE_KEY_VALUE_OBSERVATION
    [_assetInput addObserver:self
                  forKeyPath:@"readyForMoreMediaData"
                     options:0
                     context:NULL];
#endif

    // Create the asset input adapter
    NSDictionary *bufferAttributes = @{ (NSString*)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB) };

    _assetInputAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_assetInput
                                                                                          sourcePixelBufferAttributes:bufferAttributes];
    NSAssert(_assetInputAdaptor, @"Cannot create asset input adaptor");

    // Create the asset writer
    NSError  *error;
#if VID_USE_QUICKTIME_MOVIE
    _assetWriter = [AVAssetWriter assetWriterWithURL:_writeURL fileType:AVFileTypeQuickTimeMovie error:&error];
#else
    _assetWriter = [AVAssetWriter assetWriterWithURL:_writeURL fileType:AVFileTypeMPEG4 error:&error];
#endif

    if (!_assetWriter)
        return;

    [_assetWriter addInput:_assetInput];

    if (![_assetWriter startWriting])
        return;

    [_assetWriter startSessionAtSourceTime:kCMTimeZero];

    //
    // Write the frames out
    //
    for (int i = 0; i < 255; i++)
    {
        //
        // Create some "dummy" data. In a real app, this would be passed into
        // a function called per-frame, or would exist already in, say, an
        // array. Here, we fake having padded rows by adding 5 pixels' worth
        // of space in each row. This just makes sure we're communicating this
        // all correctly with the writer. Allocating on the heap to ensure we
        // dont' run into any stack-allocation issues...
        //
        long size = (VID_WIDTH + 5) * VID_HEIGHT * 4;
        UInt8 *data = new UInt8[size];
        memset(data, i % 255, size);

        NSInteger samplesPerPixel = 4;
        NSInteger bytesPerRow     = (VID_WIDTH + 5) * samplesPerPixel;
        NSInteger totalBytes      = VID_HEIGHT * bytesPerRow;

        //
        // bufferData is a COPY of the camera data and we now own it.
        // This will be released from the release callback.
        //
        CFDataRef bufferData = CFDataCreate(NULL, data, totalBytes);

        delete [] data;

        CVPixelBufferRef pixelBuffer;
        int ret = CVPixelBufferCreateWithBytes(kCFAllocatorSystemDefault,
                                               VID_WIDTH,
                                               VID_HEIGHT,
                                               k32ARGBPixelFormat,
                                               (voidPtr)CFDataGetBytePtr(bufferData), // base address
                                               bytesPerRow,
                                               ReleaseCVPixelBufferForCVPixelBufferCreateWithBytes,
                                               (void*)bufferData, // releaseRefCon
                                               NULL,              // pixelbuffer attributes dict, optional
                                               &pixelBuffer);

        if (ret != kCVReturnSuccess)
        {
            CFRelease(pixelBuffer);
            return;
        }

        //
        // Wait until the writer is ready...
        //
#if USE_KEY_VALUE_OBSERVATION
        if (!_assetInput.isReadyForMoreMediaData)
        {
            _isWaitingForInputReady = YES;
            dispatch_semaphore_wait(_writeSemaphore, DISPATCH_TIME_FOREVER);
        }
#else
        while (!_assetInput.isReadyForMoreMediaData)
        {
            usleep(1000);
        }
#endif // USE_KEY_VALUE_OBSERVATION

        //
        // Dump the frame to the writer. This is embedded in a try...catch block
        // primarily for pedagogic reasons: if you omit the asynchrony-handling
        // code just above, trying to append the pixel buffer prematurely will
        // result in an exception being thrown...
        //
        @try
        {
            if (![_assetInputAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(i, 30)])
            {
                CFRelease(pixelBuffer);
                return;
            }
        }
        @catch(NSException *theException)
        {
            NSLog(@"An exception occurred: %@", theException.name);
            NSLog(@"Here are some details: %@", theException.reason);

            CFRelease (pixelBuffer);
            return;
        }
        @finally
        {
//            NSLog(@"Executing finally block");
        }
        
        CFRelease(pixelBuffer);
        
#if VID_USE_POOL
        CFRelease(bufferData);
#endif  // VID_USE_POOL
    }

    //
    // Finalize the movie. Be sure the writer is ready...
    //
#if USE_KEY_VALUE_OBSERVATION
    if (!_assetInput.isReadyForMoreMediaData)
    {
        _isWaitingForInputReady = YES;
        dispatch_semaphore_wait(_writeSemaphore, DISPATCH_TIME_FOREVER);
    }
#else
    while (!_assetInput.isReadyForMoreMediaData)
    {
        usleep(1000);
    }
#endif // USE_KEY_VALUE_OBSERVATION

    [_assetWriter finishWritingWithCompletionHandler:^{}];

#if USE_KEY_VALUE_OBSERVATION
    [_assetInput removeObserver:self forKeyPath:@"readyForMoreMediaData"];
#endif // USE_KEY_VALUE_OBSERVATION

}


@end
