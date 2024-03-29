//
//  VideoRecodeEngine.cpp
//  Myanycam
//
//  Created by myanycam on 13-3-29.
//  Copyright (c) 2013年 Myanycam. All rights reserved.
//

#include "VideoRecodeEngine.h"
//#include "stdafx.h"

//#ifdef _DEBUG
//#undef THIS_FILE
//static char THIS_FILE[]=__FILE__;
//#define new DEBUG_NEW
//#endif


#define STREAM_NB_FRAMES  ((int)(STREAM_DURATION * STREAM_FRAME_RATE))
//#define M_PI   3.14159265358979323846
#define AV_PKT_FLAG_KEY   0x0001
#define STREAM_PIX_FMT PIX_FMT_YUV420P /* default pix_fmt */

//#define   av_alloc_format_context  avformat_alloc_output_context

/**************************************************************/
/* audio output */

float t, tincr, tincr2;
int16_t *samples;
uint8_t *audio_outbuf;
int audio_outbuf_size;
int audio_input_frame_size;

AVOutputFormat *fmt;
AVFormatContext *oc;
AVStream *audio_st, *video_st;


/*
 * add an audio output stream
 */
static AVStream *add_audio_stream(AVFormatContext *oc, enum CodecID codec_id)
{
    AVCodecContext *c;
    AVStream *st;
    
    st = av_new_stream(oc, 1);
    if (!st)
	{
        fprintf(stderr, "Could not alloc stream\n");
        return NULL;
    }
    
    st->id = 1;
    c = st->codec;
    c->codec_id = codec_id;
    c->codec_type = AVMEDIA_TYPE_AUDIO;//CODEC_TYPE_AUDIO;
    
    /* put sample parameters */
    c->sample_fmt = AV_SAMPLE_FMT_S16;
    c->bit_rate = 64000;
    c->sample_rate = 8000;
    c->channels = 1;
    
    // some formats want stream headers to be separate
    if(oc->oformat->flags & AVFMT_GLOBALHEADER)
	{
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
	}
    
    return st;
}

static void open_audio(AVFormatContext *oc, AVStream *st)
{
    AVCodecContext *c;
    AVCodec *codec;
    
    c = st->codec;
    
    /* find the audio encoder */
    codec = avcodec_find_encoder(c->codec_id);
    if (!codec)
	{
        fprintf(stderr, "codec not found\n");
        return ;
    }
    
    /* open it */
    if (avcodec_open(c, codec) < 0)
	{
        fprintf(stderr, "could not open codec\n");
        return ;
    }
    
    /* init signal generator */
    t = 0;
    tincr = 2 * M_PI * 110.0 / c->sample_rate;
    /* increment frequency by 110 Hz per second */
    tincr2 = 2 * M_PI * 110.0 / c->sample_rate / c->sample_rate;
    
    audio_outbuf_size = 10000;
    audio_outbuf = (uint8_t *) av_malloc(audio_outbuf_size);
    
    /* ugly hack for PCM codecs (will be removed ASAP with new PCM
     support to compute the input frame size in samples */
    if (c->frame_size <= 1) {
        audio_input_frame_size = audio_outbuf_size / c->channels;
        switch(st->codec->codec_id) {
            case CODEC_ID_PCM_S16LE:
            case CODEC_ID_PCM_S16BE:
            case CODEC_ID_PCM_U16LE:
            case CODEC_ID_PCM_U16BE:
                audio_input_frame_size >>= 1;
                break;
            default:
                break;
        }
    } else {
        audio_input_frame_size = c->frame_size;
    }
    samples = (int16_t *)av_malloc(audio_input_frame_size * 2 * c->channels);
}

static void close_audio(AVFormatContext *oc, AVStream *st)
{
    avcodec_close(st->codec);
    
    av_free(samples);
    av_free(audio_outbuf);
}

/**************************************************************/
/* video output */

AVFrame *picture, *tmp_picture;
uint8_t *video_outbuf;
int frame_count, video_outbuf_size;

/* add a video output stream */
static AVStream *add_video_stream(AVFormatContext *oc, enum CodecID codec_id)
{
    AVCodecContext *c;
    AVStream *st;
    
    st = av_new_stream(oc, NULL);
    if (!st)
	{
        fprintf(stderr, "Could not alloc stream\n");
        return NULL;
    }
    
    c = st->codec;
    c->codec_id = codec_id;
    c->codec_type = AVMEDIA_TYPE_VIDEO;//CODEC_TYPE_VIDEO;
    
    /* put sample parameters */
    c->bit_rate = 0; //3000000;
    /* resolution must be a multiple of two */
    c->width = 320;
    c->height = 240;
    /* time base: this is the fundamental unit of time (in seconds) in terms
     of which frame timestamps are represented. for fixed-fps content,
     timebase should be 1/framerate and timestamp increments should be
     identically 1. */
    c->time_base.den = 15;
    c->time_base.num = 1;
	c->frame_number = 1;
    c->gop_size = 12; /* emit one intra frame every twelve frames at most */
    c->pix_fmt = STREAM_PIX_FMT;
    if (c->codec_id == CODEC_ID_MPEG2VIDEO) {
        /* just for testing, we also add B frames */
        c->max_b_frames = 2;
    }
    if (c->codec_id == CODEC_ID_MPEG1VIDEO){
        /* Needed to avoid using macroblocks in which some coeffs overflow.
         This does not happen with normal video, it just happens here as
         the motion of the chroma plane does not match the luma plane. */
        c->mb_decision=2;
    }
    // some formats want stream headers to be separate
    if(oc->oformat->flags & AVFMT_GLOBALHEADER)
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
    
    return st;
}

static AVFrame *alloc_picture(enum PixelFormat pix_fmt, int width, int height)
{
    AVFrame *picture;
    uint8_t *picture_buf;
    int size;
    
    picture = avcodec_alloc_frame();
    if (!picture)
        return NULL;
    size = avpicture_get_size(pix_fmt, width, height);
    picture_buf = (uint8_t *)av_malloc(size);
    if (!picture_buf) {
        av_free(picture);
        return NULL;
    }
    avpicture_fill((AVPicture *)picture, picture_buf,
                   pix_fmt, width, height);
    return picture;
}

static void open_video(AVFormatContext *oc, AVStream *st)
{
    AVCodec *codec;
    AVCodecContext *c;
    
    c = st->codec;
    
    /* find the video encoder */
    codec = avcodec_find_encoder(c->codec_id);
    if (!codec)
	{
        fprintf(stderr, "codec not found\n");
        return;
    }
    
    /* open the codec */
    if (avcodec_open(c, codec) < 0) {
        fprintf(stderr, "could not open codec\n");
        return;
    }
    
    video_outbuf = NULL;
    if (!(oc->oformat->flags & AVFMT_RAWPICTURE)) {
        /* allocate output buffer */
        /* XXX: API change will be done */
        /* buffers passed into lav* can be allocated any way you prefer,
         as long as they're aligned enough for the architecture, and
         they're freed appropriately (such as using av_free for buffers
         allocated with av_malloc) */
        video_outbuf_size = 200000;
        video_outbuf = (uint8_t *)av_malloc(video_outbuf_size);
    }
    
    /* allocate the encoded raw picture */
    picture = alloc_picture(c->pix_fmt, c->width, c->height);
    if (!picture)
	{
        fprintf(stderr, "Could not allocate picture\n");
        return;
    }
    
    /* if the output format is not YUV420P, then a temporary YUV420P
     picture is needed too. It is then converted to the required
     output format */
    tmp_picture = NULL;
    if (c->pix_fmt != PIX_FMT_YUV420P)
	{
        tmp_picture = alloc_picture(PIX_FMT_YUV420P, c->width, c->height);
        if (!tmp_picture)
		{
            fprintf(stderr, "Could not allocate temporary picture\n");
            exit(1);
        }
    }
}

static void close_video(AVFormatContext *oc, AVStream *st)
{
    avcodec_close(st->codec);
    av_free(picture->data[0]);
    av_free(picture);
    if (tmp_picture) {
        av_free(tmp_picture->data[0]);
        av_free(tmp_picture);
    }
    av_free(video_outbuf);
}

/**************************************************************/
/* media file output */
bool CVideoRecorder::Create(int cx,int cy, int videotype, int audiotype, int frame,char *pfilename)
{
	/* initialize libavcodec, and register all codecs and formats */
    av_register_all();
    
    
    /* auto detect the output format from the name. default is                                                                         mpeg. */
    fmt = av_guess_format(NULL, pfilename, NULL);
    
    if (!fmt)
	{
        printf("Could not deduce output format from file extension: using MPEG.\n");
		return false;
    }
    
    //avformat_alloc_output_context2(&oc, NULL, NULL, filename);
    
    /* allocate the output media context */
    oc = avformat_alloc_context();//av_alloc_format_context();
    
    if (!oc) {
        fprintf(stderr, "Memory error\n");
        exit(1);
    }
    
	//CODEC_ID_MJPEG            =  8,
	//CODEC_ID_H264
    
	fmt->video_codec = CODEC_ID_H264;
	//fmt->audio_codec = CODEC_ID_ADPCM_MS;
    
    
	/*oc->oformat->video_codec = CODEC_ID_H264;
     oc->oformat->audio_codec = CODEC_ID_ADPCM_MS;  */
    
    // fmt = oc->oformat;
	//fmt->audio_codec = CODEC_ID_PCM_U16LE;
    oc->oformat = fmt;
    
    snprintf(oc->filename, sizeof(oc->filename), "%s", pfilename);
    
    /* add the audio and video streams using the default format codecs
     and initialize the codecs */
    video_st = NULL;
    audio_st = NULL;
    if (fmt->video_codec != CODEC_ID_NONE)
	{
        video_st = add_video_stream(oc, fmt->video_codec);
    }
    
    if (fmt->audio_codec != CODEC_ID_NONE)
    {
        audio_st = add_audio_stream(oc, fmt->audio_codec);
    }
    
    /* set the output parameters (must be done even if no
     parameters). */
    /*    if (av_set_parameters(oc, NULL) < 0)
     {
     fprintf(stderr, "Invalid output format parameters\n");
     return false;
     }  */
    
    av_dump_format(oc, 0, pfilename, 1);
    
    /* now that all the parameters are set, we can open the audio and
     video codecs and allocate the necessary encode buffers */
    if (video_st)
        open_video(oc, video_st);
    if (audio_st)
        open_audio(oc, audio_st);
    
    /* open the output file, if needed */
    if (!(fmt->flags & AVFMT_NOFILE))
	{
        if (avio_open(&oc->pb, pfilename, AVIO_FLAG_WRITE) < 0)
        {
            fprintf(stderr, "Could not open '%s'\n", pfilename);
            return false;
        }
    }
    
    /* write the stream header, if any */
    avformat_write_header(oc, NULL);//av_write_header(oc);
    
	return true;
}

bool CVideoRecorder::WriteVideo(char *pVideoBuff, int nLen)
{
	AVPacket pkt;
	av_init_packet(&pkt);
    
	pkt.stream_index = video_st->index;
	pkt.data = (uint8_t *)pVideoBuff;
	pkt.size = nLen;
    
    if(oc->oformat->video_codec == CODEC_ID_H264)
	{
        
		char szHead[5] = {0};
		memcpy(szHead,pVideoBuff,5);
        
		if((szHead[0] == 0x00) && (szHead[1] == 0x00) && (szHead[2] == 0x00)&& (szHead[3] == 0x01)&& (szHead[4] == 0x67))
		{
			pkt.flags|= AV_PKT_FLAG_KEY;
		}
	}
	else
	{
		pkt.flags|= AV_PKT_FLAG_KEY;
	}
    
	av_interleaved_write_frame(oc, &pkt);
    
	return true;
}

bool CVideoRecorder::WriteAudio(char *pAudioBuff, int nLen)
{
	AVPacket pkt;
	av_init_packet(&pkt);
    
	memcpy(audio_outbuf,pAudioBuff,nLen);
	audio_outbuf_size = nLen;
    
    
	AVCodecContext *c;
    
    
    c = audio_st->codec;
    
    
    pkt.size = avcodec_encode_audio(c, audio_outbuf, audio_outbuf_size, (const short *)pAudioBuff);
    
    
    pkt.flags |= AV_PKT_FLAG_KEY;
    pkt.stream_index = audio_st->index;
	//pkt.size = nLen;
    // pkt.data = (uint8_t *)audio_outbuf;
    
    
    
    
	//pkt.stream_index = audio_st->index;
	//pkt.data = (uint8_t *)pAudioBuff;
	//pkt.size = nLen;
    
	if(pkt.size > 0)
	{
		av_interleaved_write_frame(oc, &pkt);
	}
    
	return true;
}

void CVideoRecorder::Close(void)
{
	av_write_trailer(oc);
    
    /* close each codec */
    if (video_st)
        close_video(oc, video_st);
    if (audio_st)
        close_audio(oc, audio_st);
    
    /* free the streams */
	int i = 0;
    for(i = 0; i < oc->nb_streams; i++) {
        av_freep(&oc->streams[i]->codec);
        av_freep(&oc->streams[i]);
    }
    
    if (!(fmt->flags & AVFMT_NOFILE)) {
        /* close the output file */
        avio_close(oc->pb);//url_fclose(oc->pb);
    }
    
    /* free the stream */
    av_free(oc);
}


//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CVideoRecorder::CVideoRecorder(void)
:m_pAVCodec(NULL)
,m_pAVCodecContext(NULL)
,m_pAVFrame(NULL)
,m_nWidth(320)
,m_nHeight(240)
{
    
}

CVideoRecorder::~CVideoRecorder()
{
    
}
