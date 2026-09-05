/*
 * Copyright (c) 2026-present, the Ladybird developers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "Images.h"
#include "Networking.h"
#include <LibCore/AnonymousBuffer.h>
#include <LibCore/EventLoop.h>
#include <LibCore/ResourceImplementationFile.h>
#include <LibGfx/Bitmap.h>
#include <LibGfx/Font/FontDatabase.h>
#include <LibGfx/Font/PathFontProvider.h>
#include <LibGfx/PaintingSurface.h>
#include <LibURL/Parser.h>
#include <LibWeb/Bindings/MainThreadVM.h>
#include <LibWeb/DOM/Document.h>
#include <LibWeb/HTML/LocalTraversableNavigable.h>
#include <LibWeb/HTML/PaintConfig.h>
#include <LibWeb/HTML/Parser/HTMLParser.h>
#include <LibWeb/HTML/Parser/ParserScriptingMode.h>
#include <LibWeb/Layout/Viewport.h>
#include <LibWeb/Page/Page.h>
#include <LibWeb/Painting/DisplayListPlayerSkia.h>
#include <LibWeb/Painting/DisplayListResourceStorage.h>
#include <LibWeb/Painting/DocumentPaintState.h>
#include <LibWeb/Painting/PaintableTypes.h>
#include <LibWeb/Painting/Scrolling.h>
#include <LibWeb/Platform/EventLoopPlugin.h>
#include <LibWeb/Platform/FontPlugin.h>

#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>

namespace {

static void load_system_fonts(Gfx::PathFontProvider& provider)
{
    // Ask CoreText for accessible font files instead of assuming an iOS filesystem layout.
    auto collection = CTFontCollectionCreateFromAvailableFonts(nullptr);
    auto descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection);
    auto loadedDirectories = [NSMutableSet<NSString*> set];
    if (descriptors) {
        for (CFIndex i = 0; i < CFArrayGetCount(descriptors); ++i) {
            auto descriptor = static_cast<CTFontDescriptorRef>(CFArrayGetValueAtIndex(descriptors, i));
            auto attribute = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute);
            if (!attribute)
                continue;
            if (CFGetTypeID(attribute) == CFURLGetTypeID()) {
                auto url = (__bridge NSURL*)attribute;
                if (url.isFileURL) {
                    auto path = url.path.stringByDeletingLastPathComponent;
                    if (![loadedDirectories containsObject:path]) {
                        [loadedDirectories addObject:path];
                        provider.load_all_fonts_from_uri(MUST(String::formatted("file://{}",
                            StringView { path.UTF8String, [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] })));
                    }
                }
            }
            CFRelease(attribute);
        }
        CFRelease(descriptors);
    }
    CFRelease(collection);
}

class IOSFontProvider final : public Gfx::SystemFontProvider {
public:
    IOSFontProvider()
    {
        load_system_fonts(m_fonts);
        m_fonts.load_all_fonts_from_uri("resource://fonts"sv);
    }

    virtual StringView name() const override { return "iOS"sv; }

    virtual RefPtr<Gfx::Font> get_font(FlyString const& family, float size, unsigned weight, unsigned width, unsigned slope, Optional<Gfx::FontVariationSettings> const& variations, Optional<Gfx::ShapeFeatures> const& features) override
    {
        return m_fonts.get_font(family, size, weight, width, slope, variations, features);
    }

    virtual void for_each_typeface_with_family_name(FlyString const& family, Function<void(Gfx::Typeface const&)> callback) override
    {
        m_fonts.for_each_typeface_with_family_name(family, move(callback));
    }

    virtual Optional<FlyString> resolve_generic_family(StringView family, u16 weight, u8 slope) override
    {
        FlyString preferred = "Helvetica"_fly_string;
        if (family == "serif"sv)
            preferred = "Times New Roman"_fly_string;
        else if (family == "monospace"sv)
            preferred = "Courier New"_fly_string;
        else if (family == "cursive"sv)
            preferred = "Snell Roundhand"_fly_string;
        else if (family == "fantasy"sv)
            preferred = "Papyrus"_fly_string;
        if (m_fonts.get_font(preferred, 12, weight, Gfx::FontWidth::Normal, slope))
            return preferred;
        return "SerenitySans"_fly_string;
    }

private:
    Gfx::PathFontProvider m_fonts;
};

class DemoPageClient final : public Web::PageClient {
    GC_CELL(DemoPageClient, Web::PageClient);
    GC_DECLARE_ALLOCATOR(DemoPageClient);

public:
    static GC::Ref<DemoPageClient> create()
    {
        return Web::Bindings::main_thread_vm().heap().allocate<DemoPageClient>();
    }

    void initialize()
    {
        m_page = Web::Page::create(*this);
        m_page->set_is_scripting_enabled(false);
        m_page->set_top_level_traversable(Web::HTML::LocalTraversableNavigable::create_a_new_top_level_traversable(*m_page, nullptr, {}, {}, Web::HTML::VisibilityState::Visible));
    }

    void parse(StringView html, URL::URL const& url)
    {
        auto document = m_page->top_level_traversable()->active_document();
        document->remove_all_children();
        document->set_url(url);
        document->set_origin(url.origin());
        document->set_content_type("text/html"_utf16_fly_string);
        auto parser = Web::HTML::HTMLParser::create_from_byte_string(*document, html, Web::HTML::ParserScriptingMode::Disabled, "UTF-8"sv);
        parser->run(url);
    }

    Gfx::IntSize content_size() const { return m_content_size; }

    RefPtr<Gfx::Bitmap> render(int width, int height, int scroll_x, int scroll_y, double scale)
    {
        bool scale_changed = m_scale != scale;
        m_scale = scale;
        m_size = { static_cast<int>(ceil(width * scale)), static_cast<int>(ceil(height * scale)) };
        auto navigable = m_page->top_level_traversable();
        navigable->set_viewport_size({ width, height }, scale_changed ? Web::InvalidateDisplayList::Yes : Web::InvalidateDisplayList::No);
        auto document = navigable->active_document();
        document->update_layout(Web::DOM::UpdateLayoutReason::ProcessScreenshot);
        m_content_size = { width, height };
        if (auto* viewport = document->layout_node()) {
            auto maximum = Web::Painting::maximum_scroll_offset(*viewport);
            m_content_size = { width + max(0, maximum.x().to_int()), height + max(0, maximum.y().to_int()) };
        }
        navigable->perform_scroll_of_viewport_scrolling_box({ scroll_x, scroll_y });
        navigable->clamp_viewport_scroll_offset();
        document->update_paint_and_hit_testing_properties_if_needed();
        Web::Painting::DisplayListResourceStorage resources;
        auto list = document->record_display_list({}, resources, Web::Painting::PaintCommandCacheMode::ReadOnly);
        if (!list)
            return {};
        document->paint_state().refresh_scroll_state(*document);
        auto bitmap = MUST(Gfx::Bitmap::create(Gfx::BitmapFormat::BGRA8888, m_size));
        auto clear_color = list->surface_clear_color().value_or(Gfx::Color::White);
        for (int y = 0; y < m_size.height(); ++y) {
            for (int x = 0; x < m_size.width(); ++x)
                bitmap->set_pixel(x, y, clear_color);
        }
        auto surface = Gfx::PaintingSurface::wrap_bitmap(*bitmap);
        Web::Painting::DisplayListPlayerSkia player;
        player.execute(*list, document->visual_context_tree(), resources, document->scroll_state_snapshot(), surface);
        player.flush(*surface);
        return bitmap;
    }

    virtual u64 id() const override { return 1; }
    virtual Web::Page& page() override { return *m_page; }
    virtual Web::Page const& page() const override { return *m_page; }
    virtual bool is_connection_open() const override { return true; }
    virtual Gfx::Palette palette() const override { return Gfx::Palette(*m_palette); }
    virtual Web::DevicePixelRect screen_rect() const override { return { 0, 0, m_size.width(), m_size.height() }; }
    virtual double zoom_level() const override { return 1; }
    virtual double device_pixel_ratio() const override { return m_scale; }
    virtual double device_pixels_per_css_pixel() const override { return m_scale; }
    virtual Web::CSS::PreferredColorScheme preferred_color_scheme() const override { return Web::CSS::PreferredColorScheme::Light; }
    virtual Web::CSS::PreferredContrast preferred_contrast() const override { return Web::CSS::PreferredContrast::Auto; }
    virtual Web::CSS::PreferredMotion preferred_motion() const override { return Web::CSS::PreferredMotion::Reduce; }
    virtual size_t screen_count() const override { return 1; }
    virtual Queue<Web::QueuedInputEvent>& input_event_queue() override { return m_input_events; }
    virtual void report_finished_handling_input_event(u64, Web::EventResult) override { }
    virtual Web::HTML::CrossProcessId allocate_cross_process_id() override { return m_ids.allocate(); }
    virtual void request_frame() override { }
    virtual void request_file(Web::FileRequest) override { }
    virtual bool is_headless() const override { return true; }

private:
    DemoPageClient()
    {
        auto buffer = MUST(Core::AnonymousBuffer::create_with_size(sizeof(Gfx::SystemTheme)));
        auto* theme = buffer.data<Gfx::SystemTheme>();
        theme->color[to_underlying(Gfx::ColorRole::Window)] = Gfx::Color(Gfx::Color::White).value();
        theme->color[to_underlying(Gfx::ColorRole::WindowText)] = Gfx::Color(Gfx::Color::Black).value();
        m_palette = Gfx::PaletteImpl::create_with_anonymous_buffer(move(buffer));
    }

    virtual void visit_edges(JS::Cell::Visitor& visitor) override
    {
        Base::visit_edges(visitor);
        visitor.visit(m_page);
    }

    GC::Ptr<Web::Page> m_page;
    RefPtr<Gfx::PaletteImpl> m_palette;
    Gfx::IntSize m_size { 390, 700 };
    Gfx::IntSize m_content_size;
    double m_scale { 1 };
    Queue<Web::QueuedInputEvent> m_input_events;
    Web::HTML::CrossProcessIdAllocator m_ids { .namespace_id = 1 };
};

GC_DEFINE_ALLOCATOR(DemoPageClient);

}

@interface DemoViewController : UIViewController <UITextFieldDelegate, UIScrollViewDelegate>
@end

@implementation DemoViewController
{
    UIImageView* _imageView;
    UIScrollView* _scrollView;
    UILabel* _statusLabel;
    UITextField* _urlField;
    NSURLSessionDataTask* _loadTask;
    NSUInteger _loadGeneration;
    GC::Root<DemoPageClient> _client;
    BOOL _loaded;
    BOOL _rendering;
    CADisplayLink* _displayLink;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    _urlField = [[UITextField alloc] init];
    _urlField.borderStyle = UITextBorderStyleRoundedRect;
    _urlField.placeholder = @"Enter URL";
    _urlField.accessibilityLabel = @"Address";
    _urlField.keyboardType = UIKeyboardTypeURL;
    _urlField.returnKeyType = UIReturnKeyGo;
    _urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    _urlField.spellCheckingType = UITextSpellCheckingTypeNo;
    _urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _urlField.delegate = self;
    _urlField.text = [NSUserDefaults.standardUserDefaults stringForKey:@"URL"] ?: @"https://www.dr.dk/";
    [self.view addSubview:_urlField];
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.delegate = self;
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _scrollView.bounces = NO;
    [self.view addSubview:_scrollView];
    _imageView = [[UIImageView alloc] init];
    _imageView.contentMode = UIViewContentModeScaleToFill;
    [_scrollView addSubview:_imageView];
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Loading dr.dk…";
    [self.view addSubview:_statusLabel];

    Core::EventLoop::initialize_for_current_thread();
    auto resourcePath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"res"];
    StringView resource_path { resourcePath.UTF8String, [resourcePath lengthOfBytesUsingEncoding:NSUTF8StringEncoding] };
    Core::ResourceImplementation::install(make<Core::ResourceImplementationFile>(MUST(String::from_utf8(resource_path))));
    Web::Platform::EventLoopPlugin::install(*new Web::Platform::EventLoopPlugin);
    auto& installedProvider = Gfx::FontDatabase::the().install_system_font_provider(make<IOSFontProvider>());
    Web::Platform::FontPlugin::install(*new Web::Platform::FontPlugin(false, &installedProvider));
    Web::Bindings::initialize_main_thread_vm(Web::HTML::AgentType::SimilarOriginWindow);
    install_networking();
    install_image_decoder();
    _client = DemoPageClient::create();
    _client->initialize();

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(pumpEngine)];
    _displayLink.preferredFramesPerSecond = 30;
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    [self loadAddress];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    [self loadAddress];
    return YES;
}

- (void)loadAddress
{
    auto address = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!address.length)
        return;
    if (![address containsString:@"://"])
        address = [@"https://" stringByAppendingString:address];
    auto targetURL = [NSURL URLWithString:address];
    auto scheme = targetURL.scheme.lowercaseString;
    [_loadTask cancel];
    cancel_network_requests();
    auto generation = ++_loadGeneration;
    _loaded = NO;
    _scrollView.contentOffset = CGPointZero;
    _scrollView.contentSize = _scrollView.bounds.size;
    _imageView.image = nil;
    _statusLabel.hidden = NO;
    if (!targetURL.host.length || (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"])) {
        _statusLabel.text = @"Enter a valid HTTP or HTTPS URL.";
        return;
    }
    _urlField.text = targetURL.absoluteString;
    _statusLabel.text = [NSString stringWithFormat:@"Loading %@…", targetURL.host];
    auto request = [NSURLRequest requestWithURL:targetURL
                                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                timeoutInterval:30];
    _loadTask = [NSURLSession.sharedSession dataTaskWithRequest:request
                                              completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                      if (generation != self->_loadGeneration)
                                                          return;
                                                      self->_loadTask = nil;
                                                      auto httpResponse = (NSHTTPURLResponse*)response;
                                                      if (error || !data || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                                                          self->_statusLabel.text = error ? error.localizedDescription : [NSString stringWithFormat:@"Could not load page (HTTP %ld).", (long)httpResponse.statusCode];
                                                          return;
                                                      }
                                                      auto responseURL = response.URL.absoluteString;
                                                      auto url = URL::Parser::basic_parse(StringView { responseURL.UTF8String, [responseURL lengthOfBytesUsingEncoding:NSUTF8StringEncoding] });
                                                      if (!url.has_value()) {
                                                          self->_statusLabel.text = @"Invalid response URL.";
                                                          return;
                                                      }
                                                      self->_urlField.text = responseURL;
                                                      self->_client = DemoPageClient::create();
                                                      self->_client->initialize();
                                                      self->_client->parse({ static_cast<char const*>(data.bytes), data.length }, *url);
                                                      self->_loaded = YES;
                                                      [self.view setNeedsLayout];
                                                  });
                                              }];
    [_loadTask resume];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    auto bounds = self.view.safeAreaLayoutGuide.layoutFrame;
    _urlField.frame = CGRectMake(bounds.origin.x + 8, bounds.origin.y + 6, MAX(0, bounds.size.width - 16), 40);
    bounds.origin.y += 52;
    bounds.size.height = MAX(0, bounds.size.height - 52);
    _scrollView.frame = bounds;
    _statusLabel.frame = bounds;
    [self renderPage];
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView
{
    (void)scrollView;
    [self renderPage];
}

- (void)pumpEngine
{
    if (Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents) > 0 && _loaded)
        [self.view setNeedsLayout];
}

- (void)renderPage
{
    auto bounds = _scrollView.bounds;
    if (!_loaded || _rendering || bounds.size.width < 1 || bounds.size.height < 1)
        return;
    _rendering = YES;
    // Keep only a viewport-sized bitmap, even for very long pages. UIKit supplies
    // touch scrolling and inertia; LibWeb paints the corresponding scroll offset.
    auto scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    auto bitmap = _client->render(static_cast<int>(bounds.size.width), static_cast<int>(bounds.size.height),
        static_cast<int>(_scrollView.contentOffset.x), static_cast<int>(_scrollView.contentOffset.y), scale);
    auto contentSize = _client->content_size();
    _scrollView.contentSize = CGSizeMake(contentSize.width(), contentSize.height());
    _imageView.frame = _scrollView.bounds;
    if (!bitmap) {
        _statusLabel.text = @"LibWeb did not produce a frame.";
        _statusLabel.hidden = NO;
        _rendering = NO;
        return;
    }
    // Copy the pixels so UIImage can outlive the engine's bitmap.
    auto data = [NSData dataWithBytes:bitmap->scanline(0) length:bitmap->pitch() * bitmap->height()];
    auto provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    auto colorSpace = CGColorSpaceCreateDeviceRGB();
    auto image = CGImageCreate(bitmap->width(), bitmap->height(), 8, 32, bitmap->pitch(), colorSpace,
        kCGBitmapByteOrder32Little | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst), provider, nullptr, false, kCGRenderingIntentDefault);
    _imageView.image = [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp];
    _statusLabel.hidden = YES;
    CGImageRelease(image);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    _rendering = NO;
}

@end

@interface DemoAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

@implementation DemoAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    (void)application;
    (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[DemoViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char** argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(DemoAppDelegate.class));
    }
}
