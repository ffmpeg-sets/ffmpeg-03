//
//  AudioQueuePlayer.h
//  ffmpeg-demo
//
//  Created by suntongmian on 2018/1/12.
//  Copyright © 2018年 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AudioToolbox/AudioToolbox.h>

@interface AudioQueuePlayer : NSObject

- (void)playWithPCMData:(uint8_t *)pcm length:(int)length;

- (void)resetPlay;

@end
