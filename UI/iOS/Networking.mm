/*
 * Copyright (c) 2026-present, the Ladybird developers.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "Networking.h"
#include <LibWeb/Bindings/MainThreadVM.h>
#include <LibWeb/Loader/LoadRequest.h>
#include <LibWeb/Loader/ResourceLoader.h>

#import <Foundation/Foundation.h>

@interface DemoNetworkDelegate : NSObject <NSURLSessionTaskDelegate>
@end

@implementation DemoNetworkDelegate
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler
{
    (void)session;
    (void)task;
    (void)response;
    (void)request;
    // LibWeb Fetch must see redirects to enforce its redirect and CORS rules.
    completionHandler(nil);
}
@end

namespace {

NSURLSession* s_session;
NSMutableSet<NSURLSessionDataTask*>* s_tasks;
u64 s_generation;

struct Callbacks {
    GC::Root<Web::ResourceLoader::OnHeadersReceived> headers;
    GC::Root<Web::ResourceLoader::OnDataReceived> data;
    GC::Root<Web::ResourceLoader::OnComplete> complete;
    u64 generation;
};

NSString* ns_string(StringView string)
{
    return [[NSString alloc] initWithBytes:string.characters_without_null_termination() length:string.length() encoding:NSUTF8StringEncoding];
}

ByteString byte_string(NSString* string)
{
    return ByteString { string.UTF8String, [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] };
}

}

void cancel_network_requests()
{
    ++s_generation;
    for (NSURLSessionDataTask* task in s_tasks)
        [task cancel];
    [s_tasks removeAllObjects];
}

void install_networking()
{
    auto configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 60;
    configuration.HTTPMaximumConnectionsPerHost = 6;
    s_session = [NSURLSession sessionWithConfiguration:configuration delegate:[[DemoNetworkDelegate alloc] init] delegateQueue:nil];
    s_tasks = [NSMutableSet set];
    Web::ResourceLoader::initialize(Web::Bindings::main_thread_vm().heap(), [](Web::LoadRequest const& load, auto headers, auto data, auto complete) {
        // Start with stylesheets only. Scripts remain disabled in the embedding.
        if (load.method() != "GET"sv || load.destination() != Web::Fetch::Infrastructure::Request::Destination::Style) {
            complete->function()(false, {}, "Resource type is not supported by the iOS demo"sv);
            return;
        }
        auto url = [NSURL URLWithString:ns_string(load.url()->serialize())];
        auto request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
        request.HTTPShouldHandleCookies = NO;
        for (auto const& header : load.headers())
            [request setValue:ns_string(header.value) forHTTPHeaderField:ns_string(header.name)];

        // GC roots must be created, invoked, and destroyed on the engine thread.
        // Only a raw pointer crosses the NSURLSession callback queue.
        auto* callbacks = new Callbacks { move(headers), move(data), move(complete), s_generation };
        __block NSURLSessionDataTask* task;
        task = [s_session dataTaskWithRequest:request
                            completionHandler:^(NSData* body, NSURLResponse* response, NSError* error) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [s_tasks removeObject:task];
                                    task = nil;
                                    if (callbacks->generation != s_generation || error || ![response isKindOfClass:NSHTTPURLResponse.class]) {
                                        callbacks->complete->function()(false, {}, "Resource request failed or was cancelled"sv);
                                    } else if (body.length > 16 * 1024 * 1024) {
                                        callbacks->complete->function()(false, {}, "Resource exceeds the demo's 16 MiB limit"sv);
                                    } else {
                                        auto http = (NSHTTPURLResponse*)response;
                                        auto response_headers = HTTP::HeaderList::create();
                                        for (NSString* name in http.allHeaderFields) {
                                            // NSURLSession delivers a decompressed body.
                                            if ([name caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame || [name caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame)
                                                continue;
                                            response_headers->append({ byte_string(name), byte_string([http.allHeaderFields[name] description]) });
                                        }
                                        callbacks->headers->function()(nullptr, *response_headers, static_cast<u32>(http.statusCode), {}, {}, {}, Requests::CameFromCache::No);
                                        callbacks->data->function()(Requests::ResponseData::from_bytes({ static_cast<u8 const*>(body.bytes), body.length }));
                                        callbacks->complete->function()(true, {}, {});
                                    }
                                    delete callbacks;
                                });
                            }];
        [s_tasks addObject:task];
        [task resume];
    });
}
