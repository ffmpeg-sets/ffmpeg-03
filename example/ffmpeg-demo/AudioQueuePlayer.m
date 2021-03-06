//
//  AudioQueuePlayer.m
//  ffmpeg-demo
//
//  Created by suntongmian on 2018/1/12.
//  Copyright © 2018年 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import "AudioQueuePlayer.h"

#define MIN_SIZE_PER_FRAME 2000
#define QUEUE_BUFFER_SIZE 3      //队列缓冲个数

@interface AudioQueuePlayer () {
    
    AudioQueueRef audioQueue;                                 //音频播放队列
    AudioStreamBasicDescription _audioDescription;
    AudioQueueBufferRef audioQueueBuffers[QUEUE_BUFFER_SIZE]; //音频缓存
    BOOL audioQueueBufferUsed[QUEUE_BUFFER_SIZE];             //判断音频缓存是否在使用
    NSLock *sysnLock;
    OSStatus osState;
}

@end

@implementation AudioQueuePlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        sysnLock = [[NSLock alloc]init];
        
        // 播放PCM使用
        if (_audioDescription.mSampleRate <= 0) {
            //设置音频参数
            _audioDescription.mSampleRate = 48000;//采样率
            _audioDescription.mFormatID = kAudioFormatLinearPCM;
            // 下面这个是保存音频数据的方式的说明，如可以根据大端字节序或小端字节序，浮点数或整数以及不同体位去保存数据
            _audioDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            //1单声道 2双声道
            _audioDescription.mChannelsPerFrame = 1;
            //每一个packet一侦数据,每个数据包下的桢数，即每个数据包里面有多少桢
            _audioDescription.mFramesPerPacket = 1;
            //每个采样点16bit量化 语音每采样点占用位数
            _audioDescription.mBitsPerChannel = 16;
            _audioDescription.mBytesPerFrame = (_audioDescription.mBitsPerChannel / 8) * _audioDescription.mChannelsPerFrame;
            //每个数据包的bytes总数，每桢的bytes数*每个数据包的桢数
            _audioDescription.mBytesPerPacket = _audioDescription.mBytesPerFrame * _audioDescription.mFramesPerPacket;
        }
        
        // 使用player的内部线程播放 新建输出
        AudioQueueNewOutput(&_audioDescription, AudioPlayerAQInputCallback, (__bridge void * _Nullable)(self), nil, 0, 0, &audioQueue);
        
        // 设置音量
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
        
        // 初始化需要的缓冲区
        for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
            audioQueueBufferUsed[i] = false;
            
            osState = AudioQueueAllocateBuffer(audioQueue, MIN_SIZE_PER_FRAME, &audioQueueBuffers[i]);
            
            NSLog(@"第 %d 个AudioQueueAllocateBuffer 初始化结果 %d (0表示成功)", i + 1, osState);
        }
        
        osState = AudioQueueStart(audioQueue, NULL);
        if (osState != noErr) {
            NSLog(@"AudioQueueStart Error");
        }
    }
    return self;
}

- (void)resetPlay {
    if (audioQueue != nil) {
        AudioQueueReset(audioQueue);
    }
}

// 播放相关
- (void)playWithPCMData:(uint8_t *)pcm length:(int)length {
    [sysnLock lock];
    
    int i = 0;
    while (true) {
        if (!audioQueueBufferUsed[i]) {
            audioQueueBufferUsed[i] = true;
            break;
        }else {
            i++;
            if (i >= QUEUE_BUFFER_SIZE) {
                i = 0;
            }
        }
    }
    
    audioQueueBuffers[i]->mAudioDataByteSize = (unsigned int)length;
    // 把bytes的头地址开始的len字节给mAudioData
    memcpy(audioQueueBuffers[i]->mAudioData, pcm, length);
        
    //
    AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
    
    NSLog(@"本次播放数据大小: %d", length);
    [sysnLock unlock];
}

// ************************** 回调 **********************************

// 回调回来把buffer状态设为未使用
static void AudioPlayerAQInputCallback(void* inUserData,AudioQueueRef audioQueueRef, AudioQueueBufferRef audioQueueBufferRef) {
    AudioQueuePlayer *player = (__bridge AudioQueuePlayer *)inUserData;
    [player resetBufferState:audioQueueRef and:audioQueueBufferRef];
}

- (void)resetBufferState:(AudioQueueRef)audioQueueRef and:(AudioQueueBufferRef)audioQueueBufferRef {
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        // 将这个buffer设为未使用
        if (audioQueueBufferRef == audioQueueBuffers[i]) {
            audioQueueBufferUsed[i] = false;
        }
    }
}

// ************************** 内存回收 **********************************

- (void)dealloc {
    if (audioQueue != nil) {
        AudioQueueStop(audioQueue,true);
    }
    
    audioQueue = nil;
    sysnLock = nil;
}

@end


