# Linux Adapters Implementation (C++20)

This document describes C++20 implementations of adapters for the Linux platform.

**Spec Reference:** [`specs/02_02_linux.adapters.md`](../specs/02_02_linux.adapters.md)

---

## StdErrLogger : LoggerPort

Minimal logger that writes to stderr for early initialization or fallback contexts.

```cpp
#include <iostream>
#include <sstream>
#include <mutex>
#include <chrono>
#include <iomanip>

class StdErrLogger : public LoggerPort {
private:
    mutable std::mutex mutex_;
    
    std::string timestamp() const {
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
        return ss.str();
    }
    
    void log(const std::string& level, const std::string& msg) const {
        std::lock_guard lock(mutex_);
        std::cerr << "[" << timestamp() << "] [" << level << "] " << msg << std::endl;
    }

public:
    void debug(const std::string& msg) const override {
        log("DEBUG", msg);
    }
    
    void info(const std::string& msg) const override {
        log("INFO", msg);
    }
    
    void warn(const std::string& msg) const override {
        log("WARN", msg);
    }
    
    void error(const std::string& msg) const override {
        log("ERROR", msg);
    }
};
```

**Thread Safety:** Internal mutex ensures thread-safe concurrent logging.

---

## SpdlogAdapter : LoggerPort

Uses the spdlog library for structured, high-performance logging.

```cpp
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <memory>

class SpdlogAdapter : public LoggerPort {
private:
    std::shared_ptr<spdlog::logger> logger_;

public:
    explicit SpdlogAdapter(const std::string& logger_name = "harmonia",
                          const std::string& log_file = "") {
        if (log_file.empty()) {
            // Console logger only
            logger_ = spdlog::stdout_color_mt(logger_name);
        } else {
            // Rotating file logger (10MB max, 3 files)
            auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
                log_file, 1024 * 1024 * 10, 3);
            auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
            
            logger_ = std::make_shared<spdlog::logger>(
                logger_name,
                spdlog::sinks_init_list{console_sink, file_sink}
            );
            spdlog::register_logger(logger_);
        }
        
        logger_->set_level(spdlog::level::debug);
        logger_->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
    }
    
    void debug(const std::string& msg) const override {
        logger_->debug(msg);
    }
    
    void info(const std::string& msg) const override {
        logger_->info(msg);
    }
    
    void warn(const std::string& msg) const override {
        logger_->warn(msg);
    }
    
    void error(const std::string& msg) const override {
        logger_->error(msg);
    }
};
```

**Thread Safety:** spdlog is thread-safe by default.

---

## SteadyClockAdapter : ClockPort

Provides monotonic time using `std::chrono::steady_clock`.

```cpp
#include <chrono>
#include <cstdint>

class SteadyClockAdapter : public ClockPort {
public:
    uint64_t now() const override {
        auto now = std::chrono::steady_clock::now();
        auto duration = now.time_since_epoch();
        return std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
    }
};
```

**Precision:** Returns nanoseconds. If `steady_clock` has lower precision on some systems, it's still converted to nanoseconds.

**Thread Safety:** `steady_clock::now()` is thread-safe and wait-free.

---

## PosixFileAccessAdapter : FileAccessPort

Wraps POSIX file I/O syscalls with proper error handling.

```cpp
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cerrno>
#include <cstring>
#include <unordered_map>
#include <mutex>
#include <string>

struct FileHandleToken {
    int fd;
    
    bool operator==(const FileHandleToken& other) const {
        return fd == other.fd;
    }
};

// Hash specialization for FileHandleToken
namespace std {
    template<>
    struct hash<FileHandleToken> {
        size_t operator()(const FileHandleToken& token) const {
            return std::hash<int>{}(token.fd);
        }
    };
}

class PosixFileAccessAdapter : public FileAccessPort {
private:
    std::unordered_map<FileHandleToken, int> handles_;
    mutable std::mutex mutex_;
    int next_token_ = 1000;
    
    CoreError mapErrno(const std::string& context) const {
        switch (errno) {
            case ENOENT:
                return CoreError::NotFound(context + ": File not found");
            case EACCES:
            case EPERM:
                return CoreError::IoError(context + ": Permission denied");
            case EINVAL:
                return CoreError::InvalidArgument(context + ": Invalid argument");
            default:
                return CoreError::IoError(context + ": " + std::strerror(errno));
        }
    }

public:
    FileHandleToken open(const std::string& url) override {
        int fd = ::open(url.c_str(), O_RDONLY);
        if (fd < 0) {
            throw mapErrno("Opening file: " + url);
        }
        
        std::lock_guard lock(mutex_);
        FileHandleToken token{next_token_++};
        handles_[token] = fd;
        return token;
    }
    
    int read(FileHandleToken token, void* buffer, int count) override {
        int fd;
        {
            std::lock_guard lock(mutex_);
            auto it = handles_.find(token);
            if (it == handles_.end()) {
                throw CoreError::InvalidState("Invalid file handle token");
            }
            fd = it->second;
        }
        
        ssize_t bytes_read;
        do {
            bytes_read = ::read(fd, buffer, count);
        } while (bytes_read < 0 && errno == EINTR);  // Retry on EINTR
        
        if (bytes_read < 0) {
            throw mapErrno("Reading file");
        }
        
        return static_cast<int>(bytes_read);
    }
    
    int64_t size(FileHandleToken token) const override {
        int fd;
        {
            std::lock_guard lock(mutex_);
            auto it = handles_.find(token);
            if (it == handles_.end()) {
                throw CoreError::InvalidState("Invalid file handle token");
            }
            fd = it->second;
        }
        
        struct stat st;
        if (fstat(fd, &st) < 0) {
            throw mapErrno("Getting file size");
        }
        
        return st.st_size;
    }
    
    void close(FileHandleToken token) override {
        std::lock_guard lock(mutex_);
        auto it = handles_.find(token);
        if (it != handles_.end()) {
            ::close(it->second);
            handles_.erase(it);
        }
    }
    
    ~PosixFileAccessAdapter() {
        // Clean up any remaining open files
        for (const auto& [token, fd] : handles_) {
            ::close(fd);
        }
    }
};
```

**Thread Safety:** Internal mutex protects the handles map. File operations on different tokens are safe to call concurrently.

**EINTR Handling:** Automatically retries on `EINTR` signal interruption.

---

## FFmpegDecoderAdapter : DecoderPort

Uses FFmpeg (libavformat, libavcodec) to decode audio files.

```cpp
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

#include <memory>
#include <unordered_map>
#include <mutex>

struct DecodeHandle {
    int id;
    bool operator==(const DecodeHandle& other) const { return id == other.id; }
};

namespace std {
    template<>
    struct hash<DecodeHandle> {
        size_t operator()(const DecodeHandle& h) const {
            return std::hash<int>{}(h.id);
        }
    };
}

struct DecoderContext {
    AVFormatContext* format_ctx = nullptr;
    AVCodecContext* codec_ctx = nullptr;
    SwrContext* swr_ctx = nullptr;
    int stream_index = -1;
    AVPacket* packet = nullptr;
    AVFrame* frame = nullptr;
    StreamInfo info;
};

class FFmpegDecoderAdapter : public DecoderPort {
private:
    std::unordered_map<DecodeHandle, std::unique_ptr<DecoderContext>> contexts_;
    std::mutex mutex_;
    int next_handle_id_ = 1;
    std::shared_ptr<LoggerPort> logger_;
    
    CoreError mapAVError(int averror, const std::string& context) const {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(averror, errbuf, sizeof(errbuf));
        
        if (averror == AVERROR(ENOENT)) {
            return CoreError::NotFound(context + ": " + errbuf);
        } else if (averror == AVERROR_DECODER_NOT_FOUND) {
            return CoreError::Unsupported(context + ": Decoder not found");
        } else if (averror == AVERROR_INVALIDDATA) {
            return CoreError::DecodeError(context + ": " + errbuf);
        } else {
            return CoreError::IoError(context + ": " + errbuf);
        }
    }

public:
    explicit FFmpegDecoderAdapter(std::shared_ptr<LoggerPort> logger)
        : logger_(logger) {
    }
    
    DecodeHandle open(const std::string& url) override {
        logger_->info("Opening file: " + url);
        
        auto ctx = std::make_unique<DecoderContext>();
        
        // Open input file
        int ret = avformat_open_input(&ctx->format_ctx, url.c_str(), nullptr, nullptr);
        if (ret < 0) {
            throw mapAVError(ret, "avformat_open_input");
        }
        
        // Retrieve stream information
        ret = avformat_find_stream_info(ctx->format_ctx, nullptr);
        if (ret < 0) {
            avformat_close_input(&ctx->format_ctx);
            throw mapAVError(ret, "avformat_find_stream_info");
        }
        
        // Find audio stream
        const AVCodec* codec = nullptr;
        ctx->stream_index = av_find_best_stream(
            ctx->format_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
        
        if (ctx->stream_index < 0) {
            avformat_close_input(&ctx->format_ctx);
            throw CoreError::Unsupported("No audio stream found");
        }
        
        AVStream* stream = ctx->format_ctx->streams[ctx->stream_index];
        
        // Allocate codec context
        ctx->codec_ctx = avcodec_alloc_context3(codec);
        if (!ctx->codec_ctx) {
            avformat_close_input(&ctx->format_ctx);
            throw CoreError::IoError("Failed to allocate codec context");
        }
        
        // Copy codec parameters
        ret = avcodec_parameters_to_context(ctx->codec_ctx, stream->codecpar);
        if (ret < 0) {
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            throw mapAVError(ret, "avcodec_parameters_to_context");
        }
        
        // Open codec
        ret = avcodec_open2(ctx->codec_ctx, codec, nullptr);
        if (ret < 0) {
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            throw mapAVError(ret, "avcodec_open2");
        }
        
        // Initialize resampler for Float32 output
        ctx->swr_ctx = swr_alloc();
        av_opt_set_int(ctx->swr_ctx, "in_channel_layout", 
                      ctx->codec_ctx->channel_layout, 0);
        av_opt_set_int(ctx->swr_ctx, "out_channel_layout", 
                      ctx->codec_ctx->channel_layout, 0);
        av_opt_set_int(ctx->swr_ctx, "in_sample_rate", 
                      ctx->codec_ctx->sample_rate, 0);
        av_opt_set_int(ctx->swr_ctx, "out_sample_rate", 
                      ctx->codec_ctx->sample_rate, 0);
        av_opt_set_sample_fmt(ctx->swr_ctx, "in_sample_fmt", 
                             ctx->codec_ctx->sample_fmt, 0);
        av_opt_set_sample_fmt(ctx->swr_ctx, "out_sample_fmt", 
                             AV_SAMPLE_FMT_FLT, 0);
        
        ret = swr_init(ctx->swr_ctx);
        if (ret < 0) {
            swr_free(&ctx->swr_ctx);
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            throw mapAVError(ret, "swr_init");
        }
        
        // Allocate packet and frame
        ctx->packet = av_packet_alloc();
        ctx->frame = av_frame_alloc();
        
        // Fill StreamInfo
        double duration = stream->duration * av_q2d(stream->time_base);
        if (duration <= 0 && ctx->format_ctx->duration > 0) {
            duration = ctx->format_ctx->duration / (double)AV_TIME_BASE;
        }
        
        ctx->info = StreamInfo{
            .duration = duration,
            .sample_rate = static_cast<double>(ctx->codec_ctx->sample_rate),
            .channels = ctx->codec_ctx->channels,
            .bit_depth = 32  // Float32 output
        };
        
        logger_->info("Opened successfully: " + 
                     std::to_string(ctx->info.duration) + "s, " +
                     std::to_string(ctx->info.sample_rate) + "Hz, " +
                     std::to_string(ctx->info.channels) + "ch");
        
        // Store context
        std::lock_guard lock(mutex_);
        DecodeHandle handle{next_handle_id_++};
        contexts_[handle] = std::move(ctx);
        return handle;
    }
    
    int read(DecodeHandle handle, float* buffer, int max_frames) override {
        DecoderContext* ctx;
        {
            std::lock_guard lock(mutex_);
            auto it = contexts_.find(handle);
            if (it == contexts_.end()) {
                throw CoreError::InvalidState("Invalid decode handle");
            }
            ctx = it->second.get();
        }
        
        int frames_written = 0;
        
        while (frames_written < max_frames) {
            int ret = avcodec_receive_frame(ctx->codec_ctx, ctx->frame);
            
            if (ret == AVERROR(EAGAIN)) {
                // Need more packets
                ret = av_read_frame(ctx->format_ctx, ctx->packet);
                if (ret < 0) {
                    if (ret == AVERROR_EOF) {
                        return frames_written;  // End of stream
                    }
                    throw mapAVError(ret, "av_read_frame");
                }
                
                if (ctx->packet->stream_index == ctx->stream_index) {
                    ret = avcodec_send_packet(ctx->codec_ctx, ctx->packet);
                    if (ret < 0) {
                        av_packet_unref(ctx->packet);
                        throw mapAVError(ret, "avcodec_send_packet");
                    }
                }
                av_packet_unref(ctx->packet);
                continue;
            } else if (ret < 0) {
                throw mapAVError(ret, "avcodec_receive_frame");
            }
            
            // Convert to Float32 interleaved
            uint8_t* output_buffer = reinterpret_cast<uint8_t*>(
                buffer + frames_written * ctx->info.channels);
            
            ret = swr_convert(
                ctx->swr_ctx,
                &output_buffer,
                max_frames - frames_written,
                const_cast<const uint8_t**>(ctx->frame->data),
                ctx->frame->nb_samples
            );
            
            if (ret < 0) {
                av_frame_unref(ctx->frame);
                throw mapAVError(ret, "swr_convert");
            }
            
            frames_written += ret;
            av_frame_unref(ctx->frame);
        }
        
        return frames_written;
    }
    
    void seek(DecodeHandle handle, double seconds) override {
        DecoderContext* ctx;
        {
            std::lock_guard lock(mutex_);
            auto it = contexts_.find(handle);
            if (it == contexts_.end()) {
                throw CoreError::InvalidState("Invalid decode handle");
            }
            ctx = it->second.get();
        }
        
        if (seconds < 0 || seconds > ctx->info.duration) {
            throw CoreError::InvalidArgument("Seek position out of range");
        }
        
        AVStream* stream = ctx->format_ctx->streams[ctx->stream_index];
        int64_t timestamp = static_cast<int64_t>(seconds / av_q2d(stream->time_base));
        
        int ret = av_seek_frame(ctx->format_ctx, ctx->stream_index, 
                               timestamp, AVSEEK_FLAG_BACKWARD);
        if (ret < 0) {
            throw mapAVError(ret, "av_seek_frame");
        }
        
        avcodec_flush_buffers(ctx->codec_ctx);
        logger_->info("Seeked to " + std::to_string(seconds) + "s");
    }
    
    StreamInfo info(DecodeHandle handle) const override {
        std::lock_guard lock(mutex_);
        auto it = contexts_.find(handle);
        if (it == contexts_.end()) {
            throw CoreError::InvalidState("Invalid decode handle");
        }
        return it->second->info;
    }
    
    void close(DecodeHandle handle) override {
        std::lock_guard lock(mutex_);
        auto it = contexts_.find(handle);
        if (it != contexts_.end()) {
            auto& ctx = it->second;
            
            if (ctx->frame) av_frame_free(&ctx->frame);
            if (ctx->packet) av_packet_free(&ctx->packet);
            if (ctx->swr_ctx) swr_free(&ctx->swr_ctx);
            if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
            if (ctx->format_ctx) avformat_close_input(&ctx->format_ctx);
            
            contexts_.erase(it);
            logger_->info("Decoder closed");
        }
    }
    
    ~FFmpegDecoderAdapter() {
        // Clean up any remaining contexts
        for (auto& [handle, ctx] : contexts_) {
            if (ctx->frame) av_frame_free(&ctx->frame);
            if (ctx->packet) av_packet_free(&ctx->packet);
            if (ctx->swr_ctx) swr_free(&ctx->swr_ctx);
            if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
            if (ctx->format_ctx) avformat_close_input(&ctx->format_ctx);
        }
    }
};
```

**Thread Safety:** Internal mutex protects the contexts map. Each decode session is independent.

**Supported Formats:** MP3, AAC, FLAC, Opus, Vorbis, WAV, AIFF, and more (depends on FFmpeg build configuration).

---

## PipeWireOutputAdapter : AudioOutputPort

Streams PCM audio to PipeWire (with ALSA fallback).

```cpp
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <atomic>
#include <thread>
#include <queue>
#include <condition_variable>

class PipeWireOutputAdapter : public AudioOutputPort {
private:
    pw_thread_loop* loop_ = nullptr;
    pw_stream* stream_ = nullptr;
    
    double sample_rate_ = 44100.0;
    int channels_ = 2;
    int frames_per_buffer_ = 512;
    
    std::atomic<bool> is_playing_{false};
    std::shared_ptr<LoggerPort> logger_;
    
    // Lock-free ring buffer for audio data
    struct RingBuffer {
        std::vector<float> data;
        std::atomic<size_t> write_pos{0};
        std::atomic<size_t> read_pos{0};
        size_t capacity;
        
        explicit RingBuffer(size_t cap) : capacity(cap) {
            data.resize(cap);
        }
        
        size_t available() const {
            size_t w = write_pos.load(std::memory_order_acquire);
            size_t r = read_pos.load(std::memory_order_acquire);
            return (w >= r) ? (w - r) : (capacity - r + w);
        }
        
        void write(const float* src, size_t count) {
            size_t w = write_pos.load(std::memory_order_relaxed);
            for (size_t i = 0; i < count; ++i) {
                data[w] = src[i];
                w = (w + 1) % capacity;
            }
            write_pos.store(w, std::memory_order_release);
        }
        
        void read(float* dst, size_t count) {
            size_t r = read_pos.load(std::memory_order_relaxed);
            for (size_t i = 0; i < count; ++i) {
                dst[i] = data[r];
                r = (r + 1) % capacity;
            }
            read_pos.store(r, std::memory_order_release);
        }
    };
    
    std::unique_ptr<RingBuffer> ring_buffer_;
    
    static void on_process(void* userdata) {
        auto* self = static_cast<PipeWireOutputAdapter*>(userdata);
        
        pw_buffer* buf = pw_stream_dequeue_buffer(self->stream_);
        if (!buf) return;
        
        spa_buffer* spa_buf = buf->buffer;
        float* dst = static_cast<float*>(spa_buf->datas[0].data);
        
        if (!dst) {
            pw_stream_queue_buffer(self->stream_, buf);
            return;
        }
        
        uint32_t stride = sizeof(float) * self->channels_;
        uint32_t n_frames = spa_buf->datas[0].maxsize / stride;
        
        size_t available = self->ring_buffer_->available();
        size_t frames_to_copy = std::min(
            static_cast<size_t>(n_frames), 
            available / self->channels_
        );
        
        if (frames_to_copy > 0) {
            self->ring_buffer_->read(dst, frames_to_copy * self->channels_);
        }
        
        // Fill remaining with silence if underrun
        if (frames_to_copy < n_frames) {
            std::fill_n(dst + frames_to_copy * self->channels_, 
                       (n_frames - frames_to_copy) * self->channels_, 
                       0.0f);
            self->logger_->warn("Buffer underrun: " + 
                              std::to_string(n_frames - frames_to_copy) + " frames");
        }
        
        spa_buf->datas[0].chunk->offset = 0;
        spa_buf->datas[0].chunk->stride = stride;
        spa_buf->datas[0].chunk->size = n_frames * stride;
        
        pw_stream_queue_buffer(self->stream_, buf);
    }

public:
    explicit PipeWireOutputAdapter(std::shared_ptr<LoggerPort> logger)
        : logger_(logger) {
        pw_init(nullptr, nullptr);
    }
    
    void configure(double sample_rate, int channels, int frames_per_buffer) override {
        sample_rate_ = sample_rate;
        channels_ = channels;
        frames_per_buffer_ = frames_per_buffer;
        
        // Allocate ring buffer (5 seconds worth)
        size_t buffer_size = static_cast<size_t>(sample_rate * channels * 5);
        ring_buffer_ = std::make_unique<RingBuffer>(buffer_size);
        
        logger_->info("Configured: " + std::to_string(sample_rate) + "Hz, " +
                     std::to_string(channels) + "ch");
    }
    
    void start() override {
        if (is_playing_.exchange(true)) {
            return;  // Already playing
        }
        
        loop_ = pw_thread_loop_new("harmonia-audio", nullptr);
        
        static const pw_stream_events stream_events = {
            .version = PW_VERSION_STREAM_EVENTS,
            .process = on_process,
        };
        
        pw_thread_loop_lock(loop_);
        
        stream_ = pw_stream_new_simple(
            pw_thread_loop_get_loop(loop_),
            "HarmoniaCore Playback",
            pw_properties_new(
                PW_KEY_MEDIA_TYPE, "Audio",
                PW_KEY_MEDIA_CATEGORY, "Playback",
                PW_KEY_MEDIA_ROLE, "Music",
                nullptr
            ),
            &stream_events,
            this
        );
        
        if (!stream_) {
            pw_thread_loop_unlock(loop_);
            throw CoreError::IoError("Failed to create PipeWire stream");
        }
        
        // Set audio format
        uint8_t buffer[1024];
        spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
        
        spa_audio_info_raw info = {};
        info.format = SPA_AUDIO_FORMAT_F32;
        info.rate = static_cast<uint32_t>(sample_rate_);
        info.channels = static_cast<uint32_t>(channels_);
        
        const spa_pod* params[1];
        params[0] = spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat, &info);
        
        pw_stream_connect(
            stream_,
            PW_DIRECTION_OUTPUT,
            PW_ID_ANY,
            static_cast<pw_stream_flags>(
                PW_STREAM_FLAG_AUTOCONNECT |
                PW_STREAM_FLAG_MAP_BUFFERS |
                PW_STREAM_FLAG_RT_PROCESS
            ),
            params, 1
        );
        
        pw_thread_loop_unlock(loop_);
        pw_thread_loop_start(loop_);
        
        logger_->info("PipeWire stream started");
    }
    
    void stop() override {
        if (!is_playing_.exchange(false)) {
            return;  // Already stopped
        }
        
        if (loop_) {
            pw_thread_loop_stop(loop_);
        }
        
        if (stream_) {
            pw_stream_destroy(stream_);
            stream_ = nullptr;
        }
        
        if (loop_) {
            pw_thread_loop_destroy(loop_);
            loop_ = nullptr;
        }
        
        logger_->info("PipeWire stream stopped");
    }
    
    int render(const float* buffer, int frame_count) override {
        if (!is_playing_) {
            throw CoreError::InvalidState("Audio output not started");
        }
        
        ring_buffer_->write(buffer, frame_count * channels_);
        return frame_count;
    }
    
    ~PipeWireOutputAdapter() {
        stop();
        pw_deinit();
    }
};
```

**Thread Safety:** Uses lock-free ring buffer for real-time audio thread communication.

**Real-Time Safety:** The `on_process` callback is real-time safe (no allocations, no blocking).

---

## TagLibTagReaderAdapter : TagReaderPort

Reads metadata using TagLib.

```cpp
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/id3v2tag.h>
#include <taglib/mpegfile.h>
#include <taglib/flacfile.h>
#include <taglib/attachedpictureframe.h>

class TagLibTagReaderAdapter : public TagReaderPort {
public:
    TagBundle read(const std::string& url) const override {
        TagLib::FileRef file(url.c_str());
        
        if (file.isNull()) {
            throw CoreError::NotFound("Cannot open file: " + url);
        }
        
        TagBundle bundle;
        
        if (auto* tag = file.tag()) {
            if (!tag->title().isEmpty()) {
                bundle.title = tag->title().to8Bit(true);
            }
            if (!tag->artist().isEmpty()) {
                bundle.artist = tag->artist().to8Bit(true);
            }
            if (!tag->album().isEmpty()) {
                bundle.album = tag->album().to8Bit(true);
            }
            if (!tag->genre().isEmpty()) {
                bundle.genre = tag->genre().to8Bit(true);
            }
            if (tag->year() > 0) {
                bundle.year = tag->year();
            }
            if (tag->track() > 0) {
                bundle.track_number = tag->track();
            }
        }
        
        // Try to read embedded artwork (ID3v2 only for now)
        if (auto* mpeg_file = dynamic_cast<TagLib::MPEG::File*>(file.file())) {
            if (auto* id3v2 = mpeg_file->ID3v2Tag()) {
                auto frame_list = id3v2->frameList("APIC");
                if (!frame_list.isEmpty()) {
                    auto* frame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(
                        frame_list.front());
                    if (frame) {
                        auto pic = frame->picture();
                        bundle.artwork_data = std::vector<uint8_t>(
                            pic.data(), pic.data() + pic.size());
                    }
                }
            }
        }
        
        return bundle;
    }
};
```

---

## TagLibTagWriterAdapter : TagWriterPort

Writes metadata using TagLib.

```cpp
class TagLibTagWriterAdapter : public TagWriterPort {
public:
    void write(const std::string& url, const TagBundle& tags) override {
        TagLib::FileRef file(url.c_str());
        
        if (file.isNull()) {
            throw CoreError::NotFound("Cannot open file: " + url);
        }
        
        auto* tag = file.tag();
        if (!tag) {
            throw CoreError::Unsupported("File format does not support tags");
        }
        
        if (tags.title) {
            tag->setTitle(TagLib::String(*tags.title, TagLib::String::UTF8));
        }
        if (tags.artist) {
            tag->setArtist(TagLib::String(*tags.artist, TagLib::String::UTF8));
        }
        if (tags.album) {
            tag->setAlbum(TagLib::String(*tags.album, TagLib::String::UTF8));
        }
        if (tags.genre) {
            tag->setGenre(TagLib::String(*tags.genre, TagLib::String::UTF8));
        }
        if (tags.year) {
            tag->setYear(*tags.year);
        }
        if (tags.track_number) {
            tag->setTrack(*tags.track_number);
        }
        
        if (!file.save()) {
            throw CoreError::IoError("Failed to save tags to file");
        }
    }
};
```

---

## Implementation Checklist

When implementing Linux adapters:

- [ ] Link against required libraries (PipeWire, FFmpeg, TagLib, spdlog)
- [ ] Handle POSIX errors properly (EINTR retries, errno mapping)
- [ ] Use thread-safe data structures (mutexes, atomics)
- [ ] Implement proper resource cleanup in destructors
- [ ] Map all platform errors to `CoreError`
- [ ] Test on multiple Linux distributions
- [ ] Verify real-time safety for audio callbacks
- [ ] Handle missing dependencies gracefully (e.g., PipeWire unavailable)