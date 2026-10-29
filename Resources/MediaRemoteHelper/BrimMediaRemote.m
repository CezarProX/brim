// Sends one transport command to one app's player, the way Control Center does,
// without activating the app. Loaded by /usr/bin/perl (brim-mediaremote.pl):
// since macOS 15.4 mediaremoted only answers Apple-signed processes.
//
// Input (environment): QS_MR_BUNDLE = target bundle identifier, QS_MR_COMMAND = MRCommand number.
//   QS_MR_BUNDLE = "*" sends to the system instead, exactly like the keyboard's play key: macOS picks
//   the now-playing app, or relaunches the last one (Music when nothing ever played).
// Output (stdout, one line): "sent <error>", "notfound", "notnowplaying" (the target is not macOS's
//   now-playing app, so the command would land elsewhere), or "invalid".
//
// The Perl-loader technique comes from ungive/mediaremote-adapter
// (https://github.com/ungive/mediaremote-adapter, BSD 3-Clause); this file is a separate implementation.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface NSObject (BrimPlayerPath)
- (id)initWithOrigin:(id)origin client:(id)client player:(id)player;
@end

typedef id (*QSOrigin)(void);
typedef void (*QSClients)(dispatch_queue_t, void (^)(id));
typedef void (*QSPlayers)(id, id, dispatch_queue_t, void (^)(id));
typedef void (*QSSend)(int, CFDictionaryRef, id, int, dispatch_queue_t, void (^)(int, CFArrayRef));
typedef Boolean (*QSSendSystem)(int, CFDictionaryRef);
typedef void (*QSNowPlayingClient)(dispatch_queue_t, void (^)(id));

/// The bundle placeholder that means "whatever macOS routes media keys to".
static NSString *const kQSSystemTarget = @"*";

static const int kAllowedCommands[] = {0, 1, 2, 4, 5}; // play, pause, toggle, next, previous

static BOOL qs_wait(dispatch_semaphore_t done) {
  return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0;
}

static void qs_finish(const char *line) {
  printf("%s\n", line);
  fflush(stdout);
}

/// Whether `bundle` is the app macOS treats as now playing. mediaremoted delivers a player path, and
/// a new elapsed time, only to that app: aimed at any other one (checked live: the YouTube Music web
/// app while Disney+ in Arc was now playing) the command silently lands on the now-playing app. So
/// every command for a particular app checks this first and is refused rather than misrouted.
static BOOL qs_is_now_playing(NSString *bundle, void *mr) {
  QSNowPlayingClient getNowPlaying = mr ? (QSNowPlayingClient)dlsym(mr, "MRMediaRemoteGetNowPlayingClient") : NULL;
  if (!getNowPlaying) return NO;
  __block id nowPlaying = nil;
  dispatch_semaphore_t asked = dispatch_semaphore_create(0);
  getNowPlaying(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(id client) {
    nowPlaying = client;
    dispatch_semaphore_signal(asked);
  });
  return qs_wait(asked) && [nowPlaying respondsToSelector:@selector(bundleIdentifier)] &&
    [[nowPlaying performSelector:@selector(bundleIdentifier)] isEqual:bundle];
}

/// Sends `command` to `bundle`'s player and writes the one-line outcome into `out`:
/// "sent <error>", "notfound" or "invalid". Shared by the one-shot and streaming modes.
static void qs_send(NSString *bundle, int command, char *out, size_t outSize) {
  @autoreleasepool {
    BOOL allowed = NO;
    for (size_t i = 0; i < sizeof(kAllowedCommands) / sizeof(int); i++) allowed |= kAllowedCommands[i] == command;
    if (!allowed || bundle.length == 0 || bundle.length > 255) { snprintf(out, outSize, "invalid"); return; }

    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if ([bundle isEqualToString:kQSSystemTarget]) {
      // No player path and no options: the same call the play key and Control Center make, so macOS
      // keeps its own routing and its implicit launch of the last player.
      QSSendSystem sendSystem = mr ? (QSSendSystem)dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
      if (!sendSystem) { snprintf(out, outSize, "invalid"); return; }
      snprintf(out, outSize, "sent %d", sendSystem(command, NULL) ? 0 : 1);
      return;
    }
    QSOrigin localOrigin = mr ? (QSOrigin)dlsym(mr, "MRMediaRemoteGetLocalOrigin") : NULL;
    QSClients getClients = mr ? (QSClients)dlsym(mr, "MRMediaRemoteGetNowPlayingClients") : NULL;
    QSPlayers getPlayers = mr ? (QSPlayers)dlsym(mr, "MRMediaRemoteGetPlayersForClient") : NULL;
    QSSend sendToPlayer = mr ? (QSSend)dlsym(mr, "MRMediaRemoteSendCommandToPlayer") : NULL;
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    if (!localOrigin || !getClients || !getPlayers || !sendToPlayer || !pathClass) { snprintf(out, outSize, "invalid"); return; }

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    id origin = localOrigin();
    __block NSArray *clients = nil;
    dispatch_semaphore_t listed = dispatch_semaphore_create(0);
    getClients(queue, ^(id result) { clients = result; dispatch_semaphore_signal(listed); });
    if (!qs_wait(listed)) { snprintf(out, outSize, "notfound"); return; }

    id target = nil;
    for (id client in clients) {
      if ([client respondsToSelector:@selector(bundleIdentifier)] &&
          [[client performSelector:@selector(bundleIdentifier)] isEqual:bundle]) { target = client; break; }
    }
    if (!target) { snprintf(out, outSize, "notfound"); return; }

    if (!qs_is_now_playing(bundle, mr)) { snprintf(out, outSize, "notnowplaying"); return; }

    __block NSArray *players = nil;
    dispatch_semaphore_t found = dispatch_semaphore_create(0);
    getPlayers(target, origin, queue, ^(id result) { players = result; dispatch_semaphore_signal(found); });
    if (!qs_wait(found) || players.count == 0) { snprintf(out, outSize, "notfound"); return; }

    id player = players.firstObject;
    id path = [NSStringFromClass([player class]) containsString:@"PlayerPath"]
      ? player : [[pathClass alloc] initWithOrigin:origin client:target player:player];
    __block int error = -1;
    dispatch_semaphore_t sent = dispatch_semaphore_create(0);
    sendToPlayer(command, NULL, path, 0, queue, ^(int result, CFArrayRef statuses) {
      error = result;
      dispatch_semaphore_signal(sent);
    });
    qs_wait(sent);
    snprintf(out, outSize, "sent %d", error);
  }
}

__attribute__((visibility("default"))) void brim_mediaremote_send(void) {
  const char *bundleEnv = getenv("QS_MR_BUNDLE");
  const char *commandEnv = getenv("QS_MR_COMMAND");
  if (!bundleEnv || !commandEnv) return qs_finish("invalid");
  char line[32];
  NSString *bundle = [NSString stringWithUTF8String:bundleEnv];
  qs_send(bundle, atoi(commandEnv), line, sizeof line);
  // The system send has no reply block: exiting at once can drop the message before mediaremoted
  // reads it (seen live: "sent 0", player unchanged). Give the connection a moment to deliver.
  if ([bundle isEqualToString:kQSSystemTarget]) usleep(300 * 1000);
  qs_finish(line);
}

// MARK: - Streaming mode
//
// `brim_mediaremote_stream` runs until stdin closes. It prints one JSON object per line on
// every MediaRemote now-playing change (event driven, no polling) and executes commands read
// from stdin, so a play/pause costs one pipe write instead of a process launch:
//   stdin : "send <id> <command> <bundle|*>"   "seek <id> <seconds> <bundle>"
//   stdout: {"type":"nowplaying",...} | {"type":"none"} | {"type":"reply","id":N,"result":"sent 0"}

typedef void (*QSRegister)(dispatch_queue_t);
typedef void (*QSInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*QSIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*QSClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*QSClientBundle)(id);
typedef void (*QSSetElapsed)(double);

static dispatch_queue_t qs_out_queue(void) {
  static dispatch_queue_t queue;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ queue = dispatch_queue_create("brim.mediaremote.out", DISPATCH_QUEUE_SERIAL); });
  return queue;
}

static void qs_emit(NSDictionary *object) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
  if (!data) return;
  dispatch_sync(qs_out_queue(), ^{
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
  });
}

static id qs_key(void *mr, const char *name) {
  void **symbol = (void **)dlsym(mr, name);
  return symbol ? (__bridge id)*symbol : nil;
}

static NSString *qs_string(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }
static double qs_number(id value) { return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0; }

/// True while a song is showing but MediaRemote has not handed over its cover yet (it often follows the title).
static BOOL qs_art_missing = NO;

static void qs_snapshot(void *mr, NSString **lastLine, NSString **lastArtKey) {
  QSInfo getInfo = (QSInfo)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
  QSIsPlaying getPlaying = (QSIsPlaying)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
  QSClient getClient = (QSClient)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
  QSClientBundle clientBundle = (QSClientBundle)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
  if (!getInfo || !getPlaying || !getClient || !clientBundle) return;
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  __block NSDictionary *info = nil;
  __block BOOL playing = NO;
  __block NSString *bundle = @"";
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_enter(group);
  getInfo(queue, ^(CFDictionaryRef result) { info = [(__bridge NSDictionary *)result copy]; dispatch_group_leave(group); });
  dispatch_group_enter(group);
  getPlaying(queue, ^(Boolean result) { playing = result; dispatch_group_leave(group); });
  dispatch_group_enter(group);
  getClient(queue, ^(id client) {
    if (client) bundle = qs_string((__bridge id)clientBundle(client));
    dispatch_group_leave(group);
  });
  if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) return;

  NSString *title = qs_string(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoTitle")]);
  NSDictionary *line;
  qs_art_missing = NO;
  if (title.length == 0 || bundle.length == 0) {
    line = @{@"type": @"none"};
  } else {
    id timestamp = info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoTimestamp")];
    double stamp = [timestamp isKindOfClass:[NSDate class]] ? [(NSDate *)timestamp timeIntervalSince1970] : [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *event = [@{
      @"type": @"nowplaying", @"bundle": bundle, @"title": title, @"playing": @(playing),
      @"artist": qs_string(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoArtist")]),
      @"album": qs_string(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoAlbum")]),
      @"duration": @(qs_number(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoDuration")])),
      @"elapsed": @(qs_number(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoElapsedTime")])),
      @"rate": @(qs_number(info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoPlaybackRate")])),
      @"timestamp": @(stamp),
    } mutableCopy];
    NSString *artKey = [NSString stringWithFormat:@"%@|%@|%@", bundle, title, event[@"album"]];
    id art = info[qs_key(mr, "kMRMediaRemoteNowPlayingInfoArtworkData")];
    qs_art_missing = !([art isKindOfClass:[NSData class]] && [(NSData *)art length] > 0);
    if ([art isKindOfClass:[NSData class]] && [(NSData *)art length] > 0 && [(NSData *)art length] <= 4000000
        && ![artKey isEqualToString:*lastArtKey]) {
      event[@"artwork"] = [(NSData *)art base64EncodedStringWithOptions:0];
      *lastArtKey = artKey;
    }
    line = event;
  }
  // Dedupe on everything except the wall clock and elapsed time of a steady playing song.
  NSMutableDictionary *comparable = [line mutableCopy];
  [comparable removeObjectsForKeys:@[@"timestamp", @"artwork"]];
  if ([line[@"playing"] boolValue]) [comparable removeObjectForKey:@"elapsed"];
  NSString *signature = [NSString stringWithFormat:@"%@", comparable];
  if ([signature isEqualToString:*lastLine] && !line[@"artwork"]) return;
  *lastLine = signature;
  qs_emit(line);
}

static void qs_handle_command(NSString *line, void *mr) {
  NSArray *parts = [line componentsSeparatedByString:@" "];
  if (parts.count < 3) return;
  NSInteger identifier = [parts[1] integerValue];
  char out[48];
  if ([parts[0] isEqualToString:@"send"] && parts.count >= 4) {
    qs_send(parts[3], [parts[2] intValue], out, sizeof out);
  } else if ([parts[0] isEqualToString:@"seek"] && parts.count >= 4) {
    // "seek <id> <seconds> <bundle>": the elapsed time goes to the now-playing app, so only when that is `bundle`.
    QSSetElapsed setElapsed = (QSSetElapsed)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    double seconds = [parts[2] doubleValue];
    NSString *bundle = parts[3];
    if (!setElapsed || seconds < 0 || seconds >= 604800 || bundle.length == 0 || bundle.length > 255) snprintf(out, sizeof out, "invalid");
    else if (!qs_is_now_playing(bundle, mr)) snprintf(out, sizeof out, "notnowplaying");
    else { setElapsed(seconds); snprintf(out, sizeof out, "sent 0"); }
  } else { snprintf(out, sizeof out, "invalid"); }
  qs_emit(@{@"type": @"reply", @"id": @(identifier), @"result": [NSString stringWithUTF8String:out]});
}

__attribute__((visibility("default"))) void brim_mediaremote_stream(void) {
  @autoreleasepool {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    QSRegister registerForNotifications = mr ? (QSRegister)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    if (!registerForNotifications) return qs_finish("{\"type\":\"unavailable\"}");
    dispatch_queue_t work = dispatch_queue_create("brim.mediaremote.work", DISPATCH_QUEUE_SERIAL);
    registerForNotifications(work);

    __block NSString *lastLine = @"";
    __block NSString *lastArtKey = @"";
    __block dispatch_source_t debounce = nil;
    __block void (^schedule)(void);
    schedule = ^{
      dispatch_async(work, ^{
        if (debounce) dispatch_source_cancel(debounce);
        debounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, work);
        dispatch_source_set_timer(debounce, dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 5 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(debounce, ^{
          NSString *line = lastLine, *key = lastArtKey;
          qs_snapshot(mr, &line, &key);
          lastLine = line; lastArtKey = key;
          // The cover can arrive a beat after the title: look again a few times before giving up.
          static int attempts = 0;
          if (qs_art_missing && attempts < 4) {
            attempts++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempts * 0.6 * NSEC_PER_SEC)), work, ^{ schedule(); });
          } else if (!qs_art_missing) { attempts = 0; }
        });
        dispatch_resume(debounce);
      });
    };
    NSArray<NSString *> *names = @[
      @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
      @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
      @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
      @"kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
    ];
    for (NSString *symbol in names) {
      id name = qs_key(mr, symbol.UTF8String);
      if (!name) continue;
      [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { schedule(); }];
    }
    schedule();

    // Commands arrive on stdin; EOF means Brim quit, so the helper exits with it.
    dispatch_queue_t commands = dispatch_queue_create("brim.mediaremote.commands", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t reader = dispatch_queue_create("brim.mediaremote.stdin", DISPATCH_QUEUE_SERIAL);
    dispatch_async(reader, ^{
      char buffer[512];
      while (fgets(buffer, sizeof buffer, stdin)) {
        NSString *line = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        dispatch_async(commands, ^{ qs_handle_command(line, mr); });
      }
      _exit(0);
    });
    CFRunLoopRun();
  }
}
