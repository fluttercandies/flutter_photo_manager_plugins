import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_manager_native_image/photo_manager_native_image.dart';
// The instrumentation panel reads package internals that apps do not need.
// ignore: implementation_imports
import 'package:photo_manager_native_image/src/native_image_metrics.dart';

void main() => runApp(const ExampleApp());

/// Column counts reachable by pinching.
const List<int> kColumnSteps = <int>[2, 3, 4, 6, 10];

/// The two thumbnail sizes this app uses. Which sizes to use is app policy.
const int kBaseSize = 128;
const int kMainSize = 320;

/// Which provider the grid uses, so the two can be measured the same way.
enum ProviderMode { native, imageProvider }

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'photo_manager_native_image example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const GalleryPage(),
    );
  }
}

/// Provider-agnostic timing: widget creation to first frame, measured through
/// `Image.frameBuilder` so both providers are scored by the same clock.
class FrameStats {
  static final FrameStats instance = FrameStats();

  int started = 0;
  int firstFrames = 0;
  int syncHits = 0;
  final List<int> latenciesMs = <int>[];
  final StreamController<int> _firstFrame = StreamController<int>.broadcast();

  Stream<int> get onFirstFrame => _firstFrame.stream;

  void reset() {
    started = 0;
    firstFrames = 0;
    syncHits = 0;
    latenciesMs.clear();
  }

  int? percentile(double p) {
    if (latenciesMs.isEmpty) {
      return null;
    }
    final List<int> sorted = List<int>.of(latenciesMs)..sort();
    return sorted[((sorted.length - 1) * p).round()];
  }

  void recordFirstFrame(int ms, {required bool sync}) {
    firstFrames++;
    if (sync) {
      syncHits++;
    } else {
      latenciesMs.add(ms);
    }
    _firstFrame.add(firstFrames);
  }
}

/// A pinch-to-zoom grid with an instrumentation panel.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> with WidgetsBindingObserver {
  List<AssetPathEntity> _albums = const <AssetPathEntity>[];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = const <AssetEntity>[];
  String? _errorText;
  int _columnIndex = 2;
  bool _loadingMore = false;
  ProviderMode _mode = ProviderMode.native;
  final ScrollController _scrollController = ScrollController();
  Drag? _drag;

  // Instrumentation.
  int _jankFrames = 0;
  int _memoryPressureEvents = 0;
  double _pinchBase = 1;
  bool _benchmarkRunning = false;
  String? _benchmarkResult;
  late final TimingsCallback _timingsCallback;
  Timer? _panelTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timingsCallback = (List<ui.FrameTiming> timings) {
      for (final ui.FrameTiming timing in timings) {
        if (timing.totalSpan.inMicroseconds > 16667) {
          _jankFrames++;
        }
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    // The panel polls instead of listening, so measuring never rebuilds the
    // grid on every event.
    _panelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    _panelTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    setState(() => _memoryPressureEvents++);
  }

  Future<void> _load() async {
    final PermissionState permission =
        await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      setState(() => _errorText = 'Photo library access was denied.');
      return;
    }
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(
        orders: <OrderOption>[
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _albums = albums);
    if (albums.isNotEmpty) {
      await _selectAlbum(albums.first);
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets = const <AssetEntity>[];
    });
    final List<AssetEntity> page =
        await album.getAssetListPaged(page: 0, size: 300);
    if (mounted && _album == album) {
      setState(() => _assets = page);
    }
  }

  Future<void> _loadMore() async {
    final AssetPathEntity? album = _album;
    if (album == null || _loadingMore) {
      return;
    }
    _loadingMore = true;
    try {
      final List<AssetEntity> more = await album.getAssetListRange(
        start: _assets.length,
        end: _assets.length + 300,
      );
      if (mounted && _album == album && more.isNotEmpty) {
        setState(() => _assets = <AssetEntity>[..._assets, ...more]);
      }
    } finally {
      _loadingMore = false;
    }
  }

  // One recognizer owns the grid: a single finger scrolls through the
  // ScrollPosition's own Drag (fling and overscroll included), two fingers
  // pinch. The grid's own drag recognizer would otherwise win the arena
  // before the second finger lands.
  void _onScaleStart(ScaleStartDetails details) {
    _pinchBase = 1;
    if (details.pointerCount == 1 && _scrollController.hasClients) {
      _drag = _scrollController.position.drag(
        DragStartDetails(globalPosition: details.focalPoint),
        () => _drag = null,
      );
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      _drag?.update(
        DragUpdateDetails(
          globalPosition: details.focalPoint,
          delta: Offset(0, details.focalPointDelta.dy),
          primaryDelta: details.focalPointDelta.dy,
        ),
      );
      return;
    }
    final double ratio = details.scale / _pinchBase;
    if (ratio > 1.35 && _columnIndex > 0) {
      _pinchBase = details.scale;
      setState(() => _columnIndex--);
    } else if (ratio < 0.74 && _columnIndex < kColumnSteps.length - 1) {
      _pinchBase = details.scale;
      setState(() => _columnIndex++);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _drag?.end(
      DragEndDetails(
        velocity: details.velocity,
        primaryVelocity: details.velocity.pixelsPerSecond.dy,
      ),
    );
    _drag = null;
  }

  void _forceMemoryPressure() {
    // ignore: invalid_use_of_protected_member
    PaintingBinding.instance.handleMemoryPressure();
    didHaveMemoryPressure();
  }

  void _resetMetrics() {
    NativeImageMetrics.instance.reset();
    FrameStats.instance.reset();
    setState(() {
      _jankFrames = 0;
      _memoryPressureEvents = 0;
      _benchmarkResult = null;
    });
  }

  void _setMode(ProviderMode mode) {
    imageCache.clear();
    imageCache.clearLiveImages();
    _resetMetrics();
    setState(() => _mode = mode);
  }

  /// Same scenario for every provider and device: cold fill, ten column
  /// changes, one scroll round trip. Prints a summary line to the console.
  Future<void> _runBenchmark() async {
    if (_benchmarkRunning || !_scrollController.hasClients) {
      return;
    }
    setState(() => _benchmarkRunning = true);
    final Stopwatch total = Stopwatch()..start();
    try {
      _scrollController.jumpTo(0);
      setState(() => _columnIndex = 2);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // Cold fill: clear everything, rebuild the visible cells, time until
      // 24 first frames have arrived.
      imageCache.clear();
      imageCache.clearLiveImages();
      _resetMetrics();
      final Stopwatch cold = Stopwatch()..start();
      final Completer<void> filled = Completer<void>();
      final StreamSubscription<int> sub =
          FrameStats.instance.onFirstFrame.listen((int n) {
        if (n >= 24 && !filled.isCompleted) {
          filled.complete();
        }
      });
      setState(() => _columnIndex = 1); // 3 columns: forces new cells
      await filled.future
          .timeout(const Duration(seconds: 15), onTimeout: () {});
      cold.stop();
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Pinch cycles.
      _resetMetrics();
      final Stopwatch pinch = Stopwatch()..start();
      const List<int> sequence = <int>[2, 4, 0, 3, 1, 4, 0, 2, 4, 2];
      for (final int index in sequence) {
        setState(() => _columnIndex = index);
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
      pinch.stop();
      final int pinchJank = _jankFrames;
      final int? pinchP50 = FrameStats.instance.percentile(0.5);
      final int? pinchP95 = FrameStats.instance.percentile(0.95);
      final int pinchStarted = FrameStats.instance.started;
      final int pinchFrames = FrameStats.instance.firstFrames;
      final NativeImageMetrics m = NativeImageMetrics.instance;
      final String nativeLine = _mode == ProviderMode.native
          ? ' native(req ${m.requested} done ${m.completed} '
              'cancel ${m.cancelled} maxInflight ${m.maxInFlight} '
              'liveBuf ${m.liveBuffers})'
          : '';

      // Scroll round trip.
      _resetMetrics();
      final double max = _scrollController.position.maxScrollExtent;
      final double target = max < 4000 ? max : 4000;
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 2500),
        curve: Curves.easeInOut,
      );
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 2500),
        curve: Curves.easeInOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final String result = '[bench] mode=${_mode.name} '
          'cold24=${cold.elapsedMilliseconds}ms | '
          'pinch: p50=$pinchP50 p95=$pinchP95 started=$pinchStarted '
          'frames=$pinchFrames jank=$pinchJank in ${pinch.elapsedMilliseconds}ms'
          '$nativeLine | '
          'scroll: p50=${FrameStats.instance.percentile(0.5)} '
          'p95=${FrameStats.instance.percentile(0.95)} '
          'started=${FrameStats.instance.started} jank=$_jankFrames | '
          'total=${total.elapsedMilliseconds}ms';
      debugPrint(result);
      setState(() => _benchmarkResult = result);
    } finally {
      setState(() => _benchmarkRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int columns = kColumnSteps[_columnIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.name ?? 'Native thumbnails'),
        actions: <Widget>[
          SegmentedButton<ProviderMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const <ButtonSegment<ProviderMode>>[
              ButtonSegment<ProviderMode>(
                value: ProviderMode.native,
                label: Text('native'),
              ),
              ButtonSegment<ProviderMode>(
                value: ProviderMode.imageProvider,
                label: Text('image_provider'),
              ),
            ],
            selected: <ProviderMode>{_mode},
            onSelectionChanged: (Set<ProviderMode> s) => _setMode(s.first),
          ),
          if (_albums.isNotEmpty)
            PopupMenuButton<AssetPathEntity>(
              icon: const Icon(Icons.photo_album_outlined),
              onSelected: _selectAlbum,
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<AssetPathEntity>>[
                for (final AssetPathEntity album in _albums)
                  PopupMenuItem<AssetPathEntity>(
                    value: album,
                    child: Text(album.name),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildGrid(columns)),
          _MetricsPanel(
            mode: _mode,
            columns: columns,
            jankFrames: _jankFrames,
            memoryPressureEvents: _memoryPressureEvents,
            benchmarkRunning: _benchmarkRunning,
            benchmarkResult: _benchmarkResult,
            onReset: _resetMetrics,
            onMemoryPressure: _forceMemoryPressure,
            onBenchmark: _runBenchmark,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(int columns) {
    if (_errorText != null) {
      return Center(child: Text(_errorText!));
    }
    if (_album == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool dense = columns >= 10;
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.extentAfter < 600) {
            _loadMore();
          }
          return false;
        },
        child: GridView.builder(
          key: ValueKey<String>('${_mode.name}-$columns'),
          controller: _scrollController,
          physics: const NeverScrollableScrollPhysics(),
          // Kept for Flutter < 3.42, where scrollCacheExtent does not exist.
          // ignore: deprecated_member_use
          cacheExtent: 600,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
          ),
          itemCount: _assets.length,
          itemBuilder: (BuildContext context, int index) {
            return _Cell(asset: _assets[index], dense: dense, mode: _mode);
          },
        ),
      ),
    );
  }
}

/// `Stack[base 128, main 320]`: the base layer is shared by every column
/// count, so pinching never re-requests it.
class _Cell extends StatelessWidget {
  const _Cell({required this.asset, required this.dense, required this.mode});

  final AssetEntity asset;
  final bool dense;
  final ProviderMode mode;

  ImageProvider _provider(int size) {
    switch (mode) {
      case ProviderMode.native:
        return NativeImageProvider(asset, size: size);
      case ProviderMode.imageProvider:
        return AssetEntityImageProvider(
          asset,
          isOriginal: false,
          thumbnailSize: ThumbnailSize.square(size),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _TimedImage(provider: _provider(kBaseSize)),
        if (!dense) _TimedImage(provider: _provider(kMainSize)),
        if (asset.type == AssetType.video && !dense)
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.play_circle, color: Colors.white, size: 18),
            ),
          ),
      ],
    );
  }
}

/// `Image` that reports widget-to-first-frame time to [FrameStats].
class _TimedImage extends StatefulWidget {
  const _TimedImage({required this.provider});

  final ImageProvider provider;

  @override
  State<_TimedImage> createState() => _TimedImageState();
}

class _TimedImageState extends State<_TimedImage> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    FrameStats.instance.started++;
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: _error,
      frameBuilder: (
        BuildContext context,
        Widget child,
        int? frame,
        bool wasSynchronouslyLoaded,
      ) {
        if (frame != null && !_reported) {
          _reported = true;
          FrameStats.instance.recordFirstFrame(
            _stopwatch.elapsedMilliseconds,
            sync: wasSynchronouslyLoaded,
          );
        }
        return child;
      },
    );
  }

  Widget _error(BuildContext context, Object error, StackTrace? stack) {
    final bool icloud = error is NativeImageException &&
        error.code == NativeImageErrorCode.icloudNotDownloaded;
    return ColoredBox(
      color: Colors.black12,
      child: Icon(
        icloud ? Icons.cloud_download_outlined : Icons.broken_image_outlined,
        size: 16,
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.mode,
    required this.columns,
    required this.jankFrames,
    required this.memoryPressureEvents,
    required this.benchmarkRunning,
    required this.benchmarkResult,
    required this.onReset,
    required this.onMemoryPressure,
    required this.onBenchmark,
  });

  final ProviderMode mode;
  final int columns;
  final int jankFrames;
  final int memoryPressureEvents;
  final bool benchmarkRunning;
  final String? benchmarkResult;
  final VoidCallback onReset;
  final VoidCallback onMemoryPressure;
  final VoidCallback onBenchmark;

  @override
  Widget build(BuildContext context) {
    final NativeImageMetrics m = NativeImageMetrics.instance;
    final FrameStats f = FrameStats.instance;
    final TextStyle style = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
    );
    String cell(String label, Object? value) => '$label ${value ?? '-'}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: DefaultTextStyle(
            style: style,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    Text(cell('mode', mode.name)),
                    Text(cell('cols', columns)),
                    Text(cell('widgets', f.started)),
                    Text(cell('frames', f.firstFrames)),
                    Text(cell('sync', f.syncHits)),
                    Text(cell('p50', f.percentile(0.5))),
                    Text(cell('p95', f.percentile(0.95))),
                    Text(cell('>16ms', jankFrames)),
                    Text(cell('memPressure', memoryPressureEvents)),
                    Text(cell('cache', imageCache.currentSize)),
                  ],
                ),
                if (mode == ProviderMode.native)
                  Wrap(
                    spacing: 12,
                    children: <Widget>[
                      Text(cell('req', m.requested)),
                      Text(cell('done', m.completed)),
                      Text(cell('cancel', m.cancelled)),
                      Text(cell('fail', m.failed)),
                      Text(cell('fallback', m.fallbacks)),
                      Text(cell('inflight', m.inFlight)),
                      Text(cell('maxInflight', m.maxInFlight)),
                      Text(
                        cell('liveBuf', m.liveBuffers),
                        style: m.liveBuffers == 0
                            ? null
                            : style.copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                if (benchmarkResult != null)
                  Text(
                    benchmarkResult!,
                    style: style.copyWith(fontSize: 10),
                  ),
                Row(
                  children: <Widget>[
                    TextButton(onPressed: onReset, child: const Text('Reset')),
                    TextButton(
                      onPressed: onMemoryPressure,
                      child: const Text('Memory pressure'),
                    ),
                    TextButton(
                      onPressed: benchmarkRunning ? null : onBenchmark,
                      child: Text(benchmarkRunning ? 'Running…' : 'Benchmark'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
