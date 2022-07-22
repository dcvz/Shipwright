#include "CoreAudioPlayer.h"
#include "spdlog/spdlog.h"
#include <iostream>

namespace Ship {
    void CoreAudioCallback(void *ptr, AudioQueueRef queue, AudioQueueBufferRef buf_ref) {
        AudioQueueBuffer *buf = buf_ref;
        int16_t *samp = (int16_t*)buf->mAudioData;
        int nsamp = buf->mAudioDataByteSize / sizeof(int16_t);
        if (ptr) {
            int16_t *p = (int16_t *)ptr;
            for (int i = 0; i < nsamp; i++) {
                samp[i] = p[i];
            }
            AudioQueueEnqueueBuffer(queue, buf_ref, 0, NULL);
        }
    }

    bool CoreAudioPlayer::Init(void) {
        OSStatus status;
        bufidx = 0;
        mDescription = AudioStreamBasicDescription();
        mDescription.mSampleRate = GetSampleRate();
        mDescription.mFormatID = kAudioFormatLinearPCM;
        mDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        mDescription.mFramesPerPacket = 1;
        mDescription.mChannelsPerFrame = 2; // Stereo
        mDescription.mBytesPerPacket = mDescription.mBytesPerFrame = 4; // Stereo
        mDescription.mBitsPerChannel = 16;
        if (AudioQueueNewOutput(&mDescription, CoreAudioCallback, NULL, NULL, NULL, 0, &mQueueRef)) {
            return false;
        }
        for (uint32_t i = 0; i < kMaxBuffers; i++) {
            if (status = AudioQueueAllocateBuffer(mQueueRef, Buffered(), &mBuffers[i])) {
                return false;
            }
            memset(mBuffers[i]->mAudioData, 0, Buffered());
            mBuffers[i]->mAudioDataByteSize = Buffered();
            CoreAudioCallback(NULL, mQueueRef, mBuffers[i]);
        }
        AudioQueueSetParameter(mQueueRef, kAudioQueueParam_Volume, 0.0);
        return true;
    }

    int CoreAudioPlayer::Buffered(void) {
        return 1024;
    }

    int CoreAudioPlayer::GetDesiredBuffered(void) {
        return 2480;
    }

    void CoreAudioPlayer::Play(const uint8_t* Buffer, uint32_t BufferLen) {
        if (!BufferLen || !Buffer) {
            return;
        }
        int32_t BufLen = BufferLen;
        static int init = 0;
        if (!init) {
            AudioQueueSetParameter(mQueueRef, kAudioQueueParam_Volume, 1.0);
            AudioQueueStart(mQueueRef, NULL);
        }
        while (BufLen > 0) {
            int bLen = BufLen;
            if (BufferLen > (uint32_t)Buffered()) {
                bLen = Buffered();
            } else {
                bLen = BufLen;
            }
            AudioQueueBuffer *buf = mBuffers[bufidx];
            buf->mAudioDataByteSize = bLen;
            CoreAudioCallback((void *)&Buffer, mQueueRef, mBuffers[bufidx]);
            bufidx = (bufidx + 1) % kMaxBuffers;
            BufLen -= bLen;  
        }
        return;
    }
}
