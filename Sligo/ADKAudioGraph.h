//
//  ADKAudioGraph.h
//  Sligo
//
//  Created by Robert Stenson on 11/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface ADKAudioGraph : NSObject

- (BOOL)power;
- (void)updateDronePitchWithPercentage:(Float32)percentage;

@end
