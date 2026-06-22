import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoDownloaderScreen extends StatefulWidget {
  const VideoDownloaderScreen({super.key});

  @override
  State<VideoDownloaderScreen> createState() => _VideoDownloaderScreenState();
}

class _VideoDownloaderScreenState extends State<VideoDownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<DownloadTask> _downloads = [];
  String _selectedQuality = 'Meilleure qualité';
  bool _audioOnly = false;

  final List<String> _qualities = [
    'Meilleure qualité',
    '720p',
    '480p',
    '360p',
    'Audio MP3',
  ];

  final List<Map<String, dynamic>> _supportedSites = [
    {'name': 'YouTube', 'icon': Icons.play_circle_filled, 'color': Color(0xFFE94560)},
    {'name': 'Lien direct', 'icon': Icons.link, 'color': Color(0xFF4ECDC4)},
    {'name': 'MP4/MP3', 'icon': Icons.music_video, 'color': Color(0xFFFF6B35)},
  ];

  bool _isYouTubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  Future<void> _addDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE94560),
          content: Text('Lien invalide. Collez un URL complet (http...)'),
        ),
      );
      return;
    }

    final task = DownloadTask(
      url: url,
      title: _extractTitle(url),
      quality: _audioOnly ? 'Audio MP3' : _selectedQuality,
      audioOnly: _audioOnly,
      addedAt: DateTime.now(),
    );

    setState(() {
      _downloads.insert(0, task);
      _urlController.clear();
    });

    await _startDownload(task);
  }

  String _extractTitle(String url) {
    try {
      final uri = Uri.parse(url);
      final v = uri.queryParameters['v'];
      if (v != null) return 'YouTube vidéo';
      final host = uri.host.replaceAll('www.', '');
      final pathParts = uri.pathSegments;
      if (pathParts.isNotEmpty) return pathParts.last;
      return host;
    } catch (_) {
      return 'Vidéo';
    }
  }

  Future<String> _getDownloadDir() async {
    if (Platform.isAndroid) {
      // Request storage permission
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
      final dir = Directory('/storage/emulated/0/Download/ANABOK');
      await dir.create(recursive: true);
      return dir.path;
    } else if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$home\\Downloads\\ANABOK');
      await dir.create(recursive: true);
      return dir.path;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/ANABOK');
      await dir.create(recursive: true);
      return dir.path;
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    setState(() {
      task.status = DownloadStatus.downloading;
      task.progress = 0;
    });

    try {
      final outputDir = await _getDownloadDir();

      if (_isYouTubeUrl(task.url)) {
        await _downloadYouTube(task, outputDir);
      } else {
        await _downloadDirect(task, outputDir);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = DownloadStatus.failed;
          task.errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _downloadYouTube(DownloadTask task, String outputDir) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(task.url);
      if (mounted) {
        setState(() => task.title = video.title);
      }

      final manifest = await yt.videos.streamsClient.getManifest(video.id);

      if (task.audioOnly || task.quality == 'Audio MP3') {
        // Audio only
        final audio = manifest.audioOnly.withHighestBitrate();
        final fileName = _sanitizeFilename('${video.title}.mp3');
        final filePath = '$outputDir/$fileName';
        final stream = yt.videos.streamsClient.get(audio);
        final file = File(filePath);
        final sink = file.openWrite();
        final total = audio.size.totalBytes;
        int received = 0;

        await for (final data in stream) {
          sink.add(data);
          received += data.length;
          if (mounted) {
            setState(() => task.progress = received / total);
          }
        }
        await sink.flush();
        await sink.close();

        if (mounted) {
          setState(() {
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
            task.savedPath = filePath;
          });
        }
      } else {
        // Video + audio (muxed for simplicity)
        MuxedStreamInfo streamInfo;
        switch (task.quality) {
          case '720p':
            streamInfo = manifest.muxed.firstWhere(
              (s) => s.videoResolution.height <= 720,
              orElse: () => manifest.muxed.withHighestBitrate(),
            );
            break;
          case '480p':
            streamInfo = manifest.muxed.firstWhere(
              (s) => s.videoResolution.height <= 480,
              orElse: () => manifest.muxed.withHighestBitrate(),
            );
            break;
          case '360p':
            streamInfo = manifest.muxed.firstWhere(
              (s) => s.videoResolution.height <= 360,
              orElse: () => manifest.muxed.withHighestBitrate(),
            );
            break;
          default:
            streamInfo = manifest.muxed.withHighestBitrate();
        }

        final ext = streamInfo.container.name;
        final fileName = _sanitizeFilename('${video.title}.$ext');
        final filePath = '$outputDir/$fileName';
        final stream = yt.videos.streamsClient.get(streamInfo);
        final file = File(filePath);
        final sink = file.openWrite();
        final total = streamInfo.size.totalBytes;
        int received = 0;

        await for (final data in stream) {
          sink.add(data);
          received += data.length;
          if (mounted) {
            setState(() => task.progress = received / total);
          }
        }
        await sink.flush();
        await sink.close();

        if (mounted) {
          setState(() {
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
            task.savedPath = filePath;
          });
        }
      }
    } finally {
      yt.close();
    }
  }

  Future<void> _downloadDirect(DownloadTask task, String outputDir) async {
    final dio = Dio();
    final uri = Uri.parse(task.url);
    final fileName = uri.pathSegments.isNotEmpty
        ? _sanitizeFilename(uri.pathSegments.last)
        : 'download_${DateTime.now().millisecondsSinceEpoch}';
    final filePath = '$outputDir/$fileName';

    await dio.download(
      task.url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => task.progress = received / total);
        }
      },
    );

    if (mounted) {
      setState(() {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.savedPath = filePath;
      });
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  void _removeDownload(DownloadTask task) {
    setState(() => _downloads.remove(task));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Input area
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A4E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Coller le lien de la vidéo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'https://youtube.com/watch?v=...',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        prefixIcon: const Icon(Icons.link, color: Colors.white38, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste, color: Colors.white38, size: 18),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              _urlController.text = data!.text!;
                            }
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFF16213E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A2A4E)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A2A4E)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE94560)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _audioOnly ? 'Audio MP3' : _selectedQuality,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF16213E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A2A4E)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A2A4E)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _qualities.map((q) => DropdownMenuItem(
                        value: q,
                        child: Text(q, style: const TextStyle(color: Colors.white)),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _audioOnly = val == 'Audio MP3';
                            if (!_audioOnly) _selectedQuality = val;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _addDownload,
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
                      label: const Text('Télécharger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Supported sites chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Text('Supporte :', style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: _supportedSites.map((site) => Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(site['name'], style: const TextStyle(color: Colors.white, fontSize: 10)),
                    avatar: Icon(site['icon'], size: 14, color: site['color']),
                    backgroundColor: const Color(0xFF1A1A2E),
                    side: BorderSide(color: site['color'], width: 0.5),
                    padding: EdgeInsets.zero,
                  )).toList(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Downloads list
        Expanded(
          child: _downloads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, size: 64, color: Colors.white12),
                      const SizedBox(height: 12),
                      const Text('Collez un lien YouTube ou direct', style: TextStyle(color: Colors.white38, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('Aucune installation externe requise', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _downloads.length,
                  itemBuilder: (ctx, i) => _buildDownloadCard(_downloads[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildDownloadCard(DownloadTask task) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (task.status) {
      case DownloadStatus.downloading:
        statusColor = const Color(0xFF4ECDC4);
        statusIcon = Icons.downloading;
        statusText = '${(task.progress * 100).toStringAsFixed(0)}%';
        break;
      case DownloadStatus.completed:
        statusColor = const Color(0xFF4CAF50);
        statusIcon = Icons.check_circle;
        statusText = 'Terminé';
        break;
      case DownloadStatus.failed:
        statusColor = const Color(0xFFE94560);
        statusIcon = Icons.error;
        statusText = 'Échec';
        break;
      default:
        statusColor = Colors.white38;
        statusIcon = Icons.hourglass_empty;
        statusText = 'En attente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A4E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: () => _removeDownload(task),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            task.quality,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: const Color(0xFF2A2A4E),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
          ],
          if (task.status == DownloadStatus.failed && task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: TextStyle(color: statusColor, fontSize: 11),
              maxLines: 3,
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _startDownload(task),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Réessayer', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE94560),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
              ),
            ),
          ],
          if (task.status == DownloadStatus.completed && task.savedPath != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => OpenFile.open(task.savedPath!),
              icon: const Icon(Icons.folder_open, size: 14),
              label: Text(
                task.savedPath!.split(Platform.isWindows ? '\\' : '/').last,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4CAF50),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule, size: 11, color: Colors.white24),
              const SizedBox(width: 4),
              Text(
                DateFormat('HH:mm').format(task.addedAt),
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum DownloadStatus { pending, downloading, completed, failed }

class DownloadTask {
  String url;
  String title;
  String quality;
  bool audioOnly;
  DateTime addedAt;
  DownloadStatus status = DownloadStatus.pending;
  double progress = 0;
  String? savedPath;
  String? errorMessage;

  DownloadTask({
    required this.url,
    required this.title,
    required this.quality,
    required this.audioOnly,
    required this.addedAt,
  });
}
