//
//  ADKAudioGraph.m
//  Sligo
//
//  Created by Robert Stenson on 11/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ADKAudioGraph.h"

@interface ADKAudioGraph () {
    AUGraph _graph;
    AudioUnit _rioUnit;
    AudioUnit _mixerUnit;
    
    AudioUnit _droneUnit;
    AudioUnit _varispeedUnit;
}

@end

@implementation ADKAudioGraph

#pragma mark public mutators

- (void)updateDronePitchWithPercentage:(Float32)percentage
{
    percentage *= 3.75;
    percentage += 0.25;
    CheckError(AudioUnitSetParameter(_varispeedUnit, kVarispeedParam_PlaybackRate, kAudioUnitScope_Global, 0, percentage, 0), "rate");
}

#pragma mark public audio interface

- (BOOL)power
{
    CheckError(AudioSessionInitialize(NULL, kCFRunLoopDefaultMode, InterruptionListener, (__bridge void *)self), "couldn't initialize audio session");
    
	UInt32 category = kAudioSessionCategory_MediaPlayback;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category), "Couldn't set category on audio session");
    
    [self setupAUGraph];
    
    return YES;
}

- (BOOL)powerOff
{
    return YES;
}

/*
 
 rioNode, rioUnit
 
 register nodes & units
 
 */

#pragma mark graph setup

- (BOOL)setupAUGraph
{
    CheckError(NewAUGraph(&_graph), "instantiate graph");
    
    AUNode rioNode = [self addNodeWithType:kAudioUnitType_Output AndSubtype:kAudioUnitSubType_RemoteIO];
    AUNode varispeedNode = [self addNodeWithType:kAudioUnitType_FormatConverter AndSubtype:kAudioUnitSubType_Varispeed];
    AUNode mixerNode = [self addNodeWithType:kAudioUnitType_Mixer AndSubtype:kAudioUnitSubType_MultiChannelMixer];
    AUNode droneNode = YES ? [self addNodeWithType:kAudioUnitType_MusicDevice AndSubtype:kAudioUnitSubType_Sampler]
    : [self addNodeWithType:kAudioUnitType_Generator AndSubtype:kAudioUnitSubType_AudioFilePlayer];
    
    CheckError(AUGraphOpen(_graph), "open graph");
    
    _rioUnit = [self unitFromNode:rioNode];
    _mixerUnit = [self unitFromNode:mixerNode];
    _droneUnit = [self unitFromNode:droneNode];
    _varispeedUnit = [self unitFromNode:varispeedNode];
    
    AudioStreamBasicDescription samplerASBD;
    UInt32 samplerASBDSize = sizeof(samplerASBD);
    memset(&samplerASBD, 0, samplerASBDSize);
    CheckError(AudioUnitGetProperty(_droneUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &samplerASBD, &samplerASBDSize), "sampler asbd get");
    CheckError(AudioUnitSetProperty(_varispeedUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &samplerASBD, samplerASBDSize), "sampler asbd set");
    
    CheckError(AUGraphConnectNodeInput(_graph, droneNode, 0, varispeedNode, 0), "drone to vari");
    CheckError(AUGraphConnectNodeInput(_graph, varispeedNode, 0, mixerNode, 0), "vari to mixer");
    CheckError(AUGraphConnectNodeInput(_graph, mixerNode, 0, rioNode, 0), "mixer to rio");
    
    CheckError(AUGraphInitialize(_graph), "initialize graph");
    CheckError(AudioSessionSetActive(1), "activate audio session");
    CheckError(AUGraphStart(_graph), "start graph");
    
    if (YES) {
        CheckError(MusicDeviceMIDIEvent(_droneUnit, 0x90, 62, 127, 0),  "note");
    } else {
        [self playFile:[self urlRefWithTitle:@"doubledrone"] inUnit:_droneUnit];
    }
    
    return YES;
}

#pragma mark private helper functions

- (CFURLRef)urlRefWithTitle:(NSString *)title
{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:title ofType:@"m4a"];
    return CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)filePath, kCFURLPOSIXPathStyle, false);
}

- (void)playFile:(CFURLRef)url inUnit:(AudioUnit)unit
{
    AudioFileID recordedFile;
    CheckError(AudioFileOpenURL(url, kAudioFileReadPermission, 0, &recordedFile), "read");
    
    CheckError(AudioUnitSetProperty(unit, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &recordedFile, sizeof(recordedFile)), "file to unit");
    
    UInt64 numPackets;
    UInt32 propSize = sizeof(numPackets);
    CheckError(AudioFileGetProperty(recordedFile, kAudioFilePropertyAudioDataPacketCount, &propSize, &numPackets), "packets");
    
    AudioStreamBasicDescription fileASBD;
    UInt32 asbdSize = sizeof(fileASBD);
    CheckError(AudioFileGetProperty(recordedFile, kAudioFilePropertyDataFormat, &asbdSize, &fileASBD), "file format");
    
    UInt32 framesToPlay = numPackets * fileASBD.mFramesPerPacket;
    
    ScheduledAudioFileRegion rgn;
    memset(&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
    rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    rgn.mTimeStamp.mSampleTime = 0;
    rgn.mCompletionProc = NULL;
    rgn.mCompletionProcUserData = NULL;
    rgn.mAudioFile = recordedFile;
    rgn.mLoopCount = -1;
    rgn.mStartFrame = 0;
    rgn.mFramesToPlay = framesToPlay;
    
    CheckError(AudioUnitSetProperty(unit, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &rgn, sizeof(rgn)), "region");
    
    AudioTimeStamp startTime;
    memset(&startTime, 0, sizeof(startTime));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    
    CheckError(AudioUnitSetProperty(unit, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)), "start time");
}

static void InterruptionListener (void *inUserData, UInt32 inInterruptionState)
{
	NSLog(@"INTERRUPTION");
}

- (AUNode)addNodeWithType:(OSType)type AndSubtype:(OSType)subtype
{
    AudioComponentDescription acd;
    AUNode node;
    
    acd.componentType = type;
    acd.componentSubType = subtype;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    
    CheckError(AUGraphAddNode(_graph, &acd, &node), "adding node");
    return node;
}

- (NSMutableDictionary *)plistWithSampleName:(NSString *)sampleName
{
#define FILE_REFERENCE_FORMAT @"/Users/robstenson/Desktop/VLF/Funklet/Funklet/Sounds/maestro/%@.wav"
#define FIRST_SAMPLE_KEY @"Sample:1"
    
    NSURL *presetURL = [[NSBundle mainBundle] URLForResource:@"Kick" withExtension:@"aupreset"];
    NSMutableDictionary *plist = [[NSMutableDictionary alloc] initWithContentsOfURL:presetURL];
    NSMutableDictionary *fileReferences = (NSMutableDictionary *)[plist objectForKey:(__bridge NSString *)CFSTR(kAUPresetExternalFileRefs)];
    [fileReferences setObject:[NSString stringWithFormat:FILE_REFERENCE_FORMAT, sampleName] forKey:FIRST_SAMPLE_KEY];
    return plist;
}

- (AudioUnit)unitFromNode:(AUNode)node
{
    AudioUnit unit;
    CheckError(AUGraphNodeInfo(_graph, node, NULL, &unit), "unit from node");
    return unit;
}

- (OSStatus)loadPresetURL:(NSString *)presetName intoUnit:(AudioUnit)unit {
    CFPropertyListRef plistRef = (__bridge CFPropertyListRef)[self plistWithSampleName:presetName];
    return AudioUnitSetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plistRef, sizeof(CFPropertyListRef));
}

- (void)printASBD: (AudioStreamBasicDescription) asbd
{    
    char formatIDString[5];
    UInt32 formatID = CFSwapInt32HostToBig (asbd.mFormatID);
    bcopy (&formatID, formatIDString, 4);
    formatIDString[4] = '\0';
    
    if (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) {
        NSLog(@"YES IT's INTEGER");
    } else if (asbd.mFormatFlags & kAudioFormatFlagIsFloat) {
        NSLog(@"YES IT's FLOAT");
    }
    
    NSLog (@"  Sample Rate:         %10.0f",  asbd.mSampleRate);
    NSLog (@"  Format ID:           %10s",    formatIDString);
    NSLog (@"  Format Flags:        %10lu",    asbd.mFormatFlags);
    NSLog (@"  Bytes per Packet:    %10lu",    asbd.mBytesPerPacket);
    NSLog (@"  Frames per Packet:   %10lu",    asbd.mFramesPerPacket);
    NSLog (@"  Bytes per Frame:     %10lu",    asbd.mBytesPerFrame);
    NSLog (@"  Channels per Frame:  %10lu",    asbd.mChannelsPerFrame);
    NSLog (@"  Bits per Channel:    %10lu",    asbd.mBitsPerChannel);
}

static void CheckError(OSStatus error, const char *operation)
{
	if (error == noErr) return;
	char str[20];
	*(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
	if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
		str[0] = str[5] = '\'';
		str[6] = '\0';
	} else {
		sprintf(str, "%d", (int)error);
    }
	fprintf(stderr, "Error: %s (%s)\n", operation, str);
}

@end
