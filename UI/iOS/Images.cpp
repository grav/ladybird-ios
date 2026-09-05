/*
 * Copyright (c) 2026-present, the Ladybird developers.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "Images.h"
#include <LibCore/EventLoop.h>
#include <LibGfx/ImageFormats/ImageDecoder.h>
#include <LibWeb/Platform/ImageCodecPlugin.h>

namespace {

using Web::Platform::DecodedImage;

ErrorOr<DecodedImage> decode_first_frame(ReadonlyBytes bytes)
{
    auto decoder = TRY(Gfx::ImageDecoder::try_create_for_raw_bytes(bytes));
    if (!decoder || decoder->frame_count() == 0)
        return Error::from_string_literal("Unsupported or invalid image");
    auto size = decoder->size();
    if (size.width() <= 0 || size.height() <= 0 || static_cast<u64>(size.width()) * size.height() > 16 * 1024 * 1024)
        return Error::from_string_literal("Image exceeds the demo's 16 megapixel limit");
    auto frame = TRY(decoder->frame(0));
    frame.image->set_alpha_type_destructive(Gfx::AlphaType::Premultiplied);
    DecodedImage result;
    result.frame_count = 1;
    result.frames.append({ move(frame.image), 0 });
    if (auto color_space = decoder->color_space(); !color_space.is_error())
        result.color_space = color_space.release_value();
    return result;
}

class IOSImageCodecPlugin final : public Web::Platform::ImageCodecPlugin {
public:
    virtual NonnullRefPtr<Core::Promise<DecodedImage>> decode_image(ReadonlyBytes bytes, Function<ErrorOr<void>(DecodedImage&)> on_resolved, Function<void(Error&)> on_rejected) override
    {
        auto promise = Core::Promise<DecodedImage>::construct();
        promise->on_resolution = move(on_resolved);
        promise->on_rejection = move(on_rejected);
        auto copy = ByteBuffer::copy(bytes);
        if (copy.is_error()) {
            promise->reject(copy.release_error());
            return promise;
        }
        // Keep callbacks asynchronous, on the engine thread. This initial port
        // decodes one frame in-process; it does not start an ImageDecoder service.
        Core::deferred_invoke([promise, bytes = copy.release_value()] {
            auto result = decode_first_frame(bytes);
            if (result.is_error())
                promise->reject(result.release_error());
            else
                promise->resolve(result.release_value());
        });
        return promise;
    }

    virtual void request_animation_frames(i64, u32, u32) override { }
    virtual void stop_animation_decode(i64) override { }
};

}

void install_image_decoder()
{
    Web::Platform::ImageCodecPlugin::install(*new IOSImageCodecPlugin);
}
