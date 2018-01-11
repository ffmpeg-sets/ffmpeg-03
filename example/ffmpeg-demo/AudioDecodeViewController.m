//
//  AudioDecodeViewController.m
//  ffmpeg-demo
//
//  Created by suntongmian on 2018/1/11.
//  Copyright © 2018年 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import "AudioDecodeViewController.h"
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libavutil/imgutils.h"
#include "libswresample/swresample.h"

@interface AudioDecodeViewController ()
{
    AVFormatContext *_pFormatContext;
    AVCodecParameters *_pVideoCodecParameters, *_pAudioCodecParameters;
    AVCodec *_pVideoCodec, *_pAudioCodec;
    AVStream *_pVideoStream, *_pAudioStream;
    AVCodecContext *_pVideoCodecContext, *_pAudioCodecContext;
    int _videoCodecOpenResult, _audioCodecOpenResult;
}
@end

@implementation AudioDecodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    backButton.frame = CGRectMake(10, 32, 100, 40);
    backButton.backgroundColor = [UIColor blueColor];
    [backButton setTitle:@"返回" forState:UIControlStateNormal];
    [backButton addTarget:self action:@selector(backButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backButton];
    
    UIButton *startButton = [UIButton buttonWithType:UIButtonTypeCustom];
    startButton.frame = CGRectMake(260, 32, 100, 40);
    startButton.backgroundColor = [UIColor blueColor];
    [startButton setTitle:@"start" forState:UIControlStateNormal];
    [startButton addTarget:self action:@selector(startButtonEvent:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:startButton];
}

- (void)startButtonEvent:(id)sender {
    [self displayAudio];
}

- (void)displayAudio {
    NSString *liveStreamingString = @"rtmp://live.hkstv.hk.lxdns.com/live/hks";
    const char *liveStreamingURL = [liveStreamingString UTF8String];
    
    av_register_all();
    
    avformat_network_init();
    
    _pFormatContext = avformat_alloc_context();
    
    if(avformat_open_input(&_pFormatContext, liveStreamingURL, NULL, NULL) != 0) {
        NSLog(@"Couldn't open input stream");
        return;
    }
    
    if(avformat_find_stream_info(_pFormatContext, NULL) < 0) {
        NSLog(@"Couldn't find stream information");
        return;
    }
    
    av_dump_format(_pFormatContext, 0, liveStreamingURL, 0);
    
    int videoIndex = -1;
    for(int i = 0; i < _pFormatContext->nb_streams; i++) {
        if(_pFormatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoIndex = i;
            break;
        }
    }
    
    if(videoIndex == -1) {
        NSLog(@"Didn't find a video stream");
    } else {
        _pVideoStream = _pFormatContext->streams[videoIndex];
    }
    
    int audioIndex = -1;
    for(int i = 0; i < _pFormatContext->nb_streams; i++) {
        if(_pFormatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioIndex = i;
            break;
        }
    }
    
    if(audioIndex == -1) {
        NSLog(@"Didn't find a audio stream");
    } else {
        _pAudioStream = _pFormatContext->streams[audioIndex];
    }
    
    if (_pVideoStream) {
        _pVideoCodecParameters = _pVideoStream->codecpar;
        _pVideoCodec = avcodec_find_decoder(_pVideoCodecParameters->codec_id);
        if(_pVideoCodec == NULL) {
            NSLog(@"Video codec not found");
        }
    }
    
    if (_pAudioStream) {
        _pAudioCodecParameters = _pAudioStream->codecpar;
        _pAudioCodec = avcodec_find_decoder(_pAudioCodecParameters->codec_id);
        if(_pAudioCodec == NULL) {
            NSLog(@"Audio codec not found");
        }
    }
    
    
    if (_pVideoCodec) {
        _pVideoCodecContext = avcodec_alloc_context3(_pVideoCodec);
        avcodec_parameters_to_context(_pVideoCodecContext, _pVideoCodecParameters);
        av_codec_set_pkt_timebase(_pVideoCodecContext, _pVideoStream->time_base);
        
        _videoCodecOpenResult = avcodec_open2(_pVideoCodecContext, _pVideoCodec, NULL);
        if(_videoCodecOpenResult != 0) {
            NSLog(@"Could not open video codec");
        }
    }
    
    if (_pAudioCodec) {
        _pAudioCodecContext = avcodec_alloc_context3(_pAudioCodec);
        avcodec_parameters_to_context(_pAudioCodecContext, _pAudioCodecParameters);
        av_codec_set_pkt_timebase(_pAudioCodecContext, _pAudioStream->time_base);
        
        _audioCodecOpenResult = avcodec_open2(_pAudioCodecContext, _pAudioCodec, NULL);
        if (_audioCodecOpenResult != 0) {
            NSLog(@"Could not open audio codec");
        }
    }
    
    if (_audioCodecOpenResult == 0) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:@"out.pcm"];
        
        FILE *fp_pcm = fopen([writablePath UTF8String], "wb");

        
        // 音频编码数据
        AVPacket *pAudioPacket = av_malloc(sizeof(AVPacket));
        // 解压后的音频数据
        AVFrame *pAudioFrame = av_frame_alloc();
       
        // 音频重采样
        SwrContext *swrContext = swr_alloc();
        // 输入的声道布局
        uint64_t in_channel_layout = _pAudioCodecContext->channel_layout;
        // 输入的采样格式
        enum AVSampleFormat in_sample_fmt = _pAudioCodecContext->sample_fmt;
        // 输入的采样率
        int in_sample_rate = _pAudioCodecContext->sample_rate;
      
        
        // 输出的声道布局
        uint64_t out_channel_layout = AV_CH_LAYOUT_MONO; // 单声道
        // 输出的采样格式 16bit, PCM
        enum AVSampleFormat out_sample_fmt = AV_SAMPLE_FMT_S16; // 16 bit
        // 输出的采样率
        int out_sample_rate = 44100; // 44100 HZ
        
        swr_alloc_set_opts(swrContext, out_channel_layout, out_sample_fmt, out_sample_rate, in_channel_layout, in_sample_fmt, in_sample_rate, 0, NULL);
        
        swr_init(swrContext);

        // 获取输出的声道个数
        int out_channel_nb = av_get_channel_layout_nb_channels(out_channel_layout);
        
        // 存储 pcm 数据
        int out_count = 2 * 44100;
        uint8_t *out_buffer = (uint8_t *)av_malloc(out_count);
        
        while(av_read_frame(_pFormatContext, pAudioPacket) >= 0) {
            if(pAudioPacket->stream_index == audioIndex) {
                avcodec_send_packet(_pAudioCodecContext, pAudioPacket);
                int ret = avcodec_receive_frame(_pAudioCodecContext, pAudioFrame);
                if (ret != 0) {
                    continue;
                }
                
                NSLog(@"Audio PCM data");

                swr_convert(swrContext, &out_buffer, out_count, pAudioFrame->data, pAudioFrame->nb_samples);
                
                // 获取 sample 的 size
                int out_buffer_size = av_samples_get_buffer_size(NULL, out_channel_nb, pAudioFrame->nb_samples, out_sample_fmt, 1);
                
                //写入文件进行测试
                fwrite(out_buffer, 1, out_buffer_size, fp_pcm);
            }
        }
        av_packet_unref(pAudioPacket);
        av_frame_free(&pAudioFrame);
        swr_free(&swrContext);
        avcodec_close(_pAudioCodecContext);
    }
}

- (void)backButtonClicked:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    avformat_close_input(&_pFormatContext);
    _pFormatContext = NULL;
    
    avcodec_free_context(&_pVideoCodecContext);
    _pVideoCodecContext = NULL;
}

@end
