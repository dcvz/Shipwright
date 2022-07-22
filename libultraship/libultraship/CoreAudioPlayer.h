#pragma once

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>
#include "AudioPlayer.h"

namespace Ship {
	void CoreAudioCallback(void *ptr, AudioQueueRef queue, AudioQueueBufferRef buf_ref);

	class CoreAudioPlayer : public AudioPlayer {
	public:
		CoreAudioPlayer() {}
		bool Init() override;
		int Buffered() override;
		int GetDesiredBuffered() override;
		void Play(const uint8_t* buff, uint32_t len) override;
	private:
		static const uint32_t kMaxBuffers = 8;
		uint32_t nsamples;
		AudioQueueRef mQueueRef;
		AudioStreamBasicDescription mDescription;
		AudioQueueBufferRef mBuffers[kMaxBuffers]; 
		uint32_t bufidx;
	};
}
#endif
