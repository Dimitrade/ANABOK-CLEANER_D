import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class VideoDownloaderScreen extends StatefulWidget {
  const VideoDownloaderScreen({super.key});

  @override
  State<VideoDownloaderScreen> createState() => _VideoDownloaderScreenState();
}

class _VideoDownloaderScreenState extends State<VideoDownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<DownloadTask> _downloads = [];
  bool _isChecking = false;
  String _selectedFormat = 'Meilleure qualité';
  bool _audioOnly = false;

  final List<String> _formats = [
    'Meilleure qualité',
    '1080p',
    '720p',
    '480p',
    '360p',
  ];

  // Supported sites indicator
  final List<Map<String, dynamic>> _supportedSites = [
    {'name': 'YouTube', 'icon': Icons.play_circle_filled, 'color': Color(0xFFE94560)},
    {'name': 'TikTok', 'icon': Icons.music_video, 'color': Color(0xFF4ECDC4)},
    {'name': 'Facebook', 'icon': Icons.facebook, 'color': Color(0xFF3B82F6)},
    {'name': 'Twitter/X', 'icon': Icons.close, 'color': Colors.white70},
    {'name': 'Instagram', 'icon': Icons.camera_alt, 'color': Color(0xFFFF6B35)},
    {'name': 'Dailymotion', 'icon': Icons.ondemand_video, 'color': Color(0xFF8B5CF6)},
  ];

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
      format: _selectedFormat,
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
      if (v != null) return 'YouTube - $v';
      final host = uri.host.replaceAll('www.', '');
      return '$host - Vidéo';
    } catch (_) {
      return 'Vidéo';
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    setState(() => task.status = DownloadStatus.downloading);

    try {
      final outputDir = await _getDownloadDirectory();
      
      if (Platform.isWindows) {
        await _downloadWindows(task, outputDir);
      } else if (Platform.isAndroid) {
        await _downloadAndroid(task, outputDir);
      } else {
        await _downloadFallback(task, outputDir);
      }
    } catch (e) {
      setState(() {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
      });
    }
  }

  Future<String> _getDownloadDirectory() async {
    if (Platform.isWindows) {
      // Windows: use Downloads folder
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$home\\Downloads\\ANABOK');
      await dir.create(recursive: true);
      return dir.path;
    } else {
      // Android
      final dir = Directory('/storage/emulated/0/Download/ANABOK');
      await dir.create(recursive: true);
      return dir.path;
    }
  }

  /// Windows: use yt-dlp executable
  Future<void> _downloadWindows(DownloadTask task, String outputDir) async {
    // Check if yt-dlp is available
    final ytdlpPath = await _findYtDlp();
    
    final qualityArgs = _getQualityArgs(task.format, task.audioOnly);
    final outputTemplate = '$outputDir\\%(title)s.%(ext)s';

    final args = [
      ...qualityArgs,
      '--output', outputTemplate,
      '--no-playlist',
      '--progress',
      task.url,
    ];

    final process = await Process.start(ytdlpPath, args);
    
    // Parse progress from stdout
    process.stdout.transform(utf8.decoder).listen((data) {
      final match = RegExp(r'(\d+\.\d+)%').firstMatch(data);
      if (match != null) {
        final pct = double.tryParse(match.group(1) ?? '0') ?? 0;
        setState(() => task.progress = pct / 100);
      }
      if (data.contains('Destination:')) {
        final pathMatch = RegExp(r'Destination:\s*(.+)').firstMatch(data);
        if (pathMatch != null) {
          task.savedPath = pathMatch.group(1)?.trim();
        }
      }
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      debugPrint('yt-dlp stderr: $data');
    });

    final exitCode = await process.exitCode;
    
    setState(() {
      if (exitCode == 0) {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = 'yt-dlp a retourné le code $exitCode';
      }
    });
  }

  /// Android: use yt-dlp via Termux or built-in
  Future<void> _downloadAndroid(DownloadTask task, String outputDir) async {
    // Try yt-dlp via shell
    final ytdlp = await _findYtDlpAndroid();
    
    if (ytdlp == null) {
      // Fallback: open in browser
      setState(() {
        task.status = DownloadStatus.failed;
        task.errorMessage = 'yt-dlp non trouvé.\nInstalle Termux + yt-dlp ou utilise la méthode navigateur.';
      });
      return;
    }

    final qualityArgs = _getQualityArgs(task.format, task.audioOnly);
    final outputTemplate = '$outputDir/%(title)s.%(ext)s';

    final args = [
      ...qualityArgs,
      '--output', outputTemplate,
      '--no-playlist',
      task.url,
    ];

    final process = await Process.start(ytdlp, args);

    process.stdout.transform(utf8.decoder).listen((data) {
      final match = RegExp(r'(\d+\.\d+)%').firstMatch(data);
      if (match != null) {
        final pct = double.tryParse(match.group(1) ?? '0') ?? 0;
        setState(() => task.progress = pct / 100);
      }
    });

    final exitCode = await process.exitCode;
    setState(() {
      task.status = exitCode == 0 ? DownloadStatus.completed : DownloadStatus.failed;
      if (exitCode == 0) task.progress = 1.0;
    });
  }

  Future<void> _downloadFallback(DownloadTask task, String outputDir) async {
    // Generic fallback
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Plateforme non supportée pour le téléchargement automatique.';
    });
  }

  Future<String> _findYtDlp() async {
    final candidates = [
      'yt-dlp',
      r'C:\yt-dlp\yt-dlp.exe',
      r'C:\Program Files\yt-dlp\yt-dlp.exe',
    ];
    for (final c in candidates) {
      try {
        final result = await Process.run(c, ['--version']);
        if (result.exitCode == 0) return c;
      } catch (_) {}
    }
    throw Exception('yt-dlp non trouvé. Veuillez l\'installer: https://github.com/yt-dlp/yt-dlp/releases');
  }

  Future<String?> _findYtDlpAndroid() async {
    final candidates = [
      '/data/data/com.termux/files/usr/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }
    return null;
  }

  List<String> _getQualityArgs(String format, bool audioOnly) {
    if (audioOnly) {
      return ['-x', '--audio-format', 'mp3', '--audio-quality', '0'];
    }
    switch (format) {
      case '1080p': return ['-f', 'bestvideo[height<=1080]+bestaudio/best[height<=1080]', '--merge-output-format', 'mp4'];
      case '720p': return ['-f', 'bestvideo[height<=720]+bestaudio/best[height<=720]', '--merge-output-format', 'mp4'];
      case '480p': return ['-f', 'bestvideo[height<=480]+bestaudio/best[height<=480]', '--merge-output-format', 'mp4'];
      case '360p': return ['-f', 'bestvideo[height<=360]+bestaudio/best[height<=360]', '--merge-output-format', 'mp4'];
      default: return ['-f', 'bestvideo+bestaudio/best', '--merge-output-format', 'mp4'];
    }
  }

  void _removeDownload(DownloadTask task) {
    setState(() => _downloads.remove(task));
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
                        fillColor: const Color(0xFF0F0F1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
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
                  // Format dropdown
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedFormat,
                        dropdownColor: const Color(0xFF1A1A2E),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        underline: const SizedBox(),
                        isExpanded: true,
                        items: _formats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                        onChanged: (v) => setState(() => _selectedFormat = v!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Audio only toggle
                  GestureDetector(
                    onTap: () => setState(() => _audioOnly = !_audioOnly),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _audioOnly ? const Color(0xFF4ECDC4).withOpacity(0.2) : const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _audioOnly ? const Color(0xFF4ECDC4) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_note, size: 14, color: _audioOnly ? const Color(0xFF4ECDC4) : Colors.white38),
                          const SizedBox(width: 4),
                          Text(
                            'MP3',
                            style: TextStyle(
                              color: _audioOnly ? const Color(0xFF4ECDC4) : Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                  onPressed: _addDownload,
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text('Télécharger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Supported sites
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sites supportés', style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _supportedSites.map((s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s['icon'] as IconData, size: 12, color: s['color'] as Color),
                    const SizedBox(width: 4),
                    Text(s['name'] as String, style: TextStyle(color: s['color'] as Color, fontSize: 11)),
                  ],
                )).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2A2A4E), height: 1),
        const SizedBox(height: 8),

        // Downloads list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${_downloads.length} téléchargement(s)',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Spacer(),
              if (_downloads.any((d) => d.status == DownloadStatus.completed))
                TextButton(
                  onPressed: () => setState(() => _downloads.removeWhere((d) => d.status == DownloadStatus.completed)),
                  child: const Text('Effacer terminés', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ),
            ],
          ),
        ),

        Expanded(
          child: _downloads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded, size: 60, color: Colors.white12),
                      const SizedBox(height: 12),
                      const Text('Collez un lien pour commencer', style: TextStyle(color: Colors.white24)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _downloads.length,
                  itemBuilder: (_, i) => _DownloadCard(
                    task: _downloads[i],
                    onRemove: () => _removeDownload(_downloads[i]),
                    onRetry: () => _startDownload(_downloads[i]),
                  ),
                ),
        ),

        // yt-dlp install note
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2A4E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF4ECDC4), size: 14),
                  const SizedBox(width: 6),
                  const Text('Prérequis', style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                Platform.isWindows
                    ? '• Télécharger yt-dlp.exe depuis github.com/yt-dlp\n• Placer dans C:\\yt-dlp\\ ou dans le PATH Windows\n• Optionnel: installer FFmpeg pour les meilleures qualités'
                    : '• Sur Android: installer Termux, puis: pkg install yt-dlp\n• Ou utiliser la version APK avec yt-dlp inclus',
                style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum DownloadStatus { pending, downloading, completed, failed }

class DownloadTask {
  final String url;
  String title;
  final String format;
  final bool audioOnly;
  final DateTime addedAt;
  DownloadStatus status;
  double progress;
  String? savedPath;
  String? errorMessage;

  DownloadTask({
    required this.url,
    required this.title,
    required this.format,
    required this.audioOnly,
    required this.addedAt,
    this.status = DownloadStatus.pending,
    this.progress = 0,
    this.savedPath,
    this.errorMessage,
  });
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  const _DownloadCard({required this.task, required this.onRemove, required this.onRetry});

  Color get _statusColor {
    switch (task.status) {
      case DownloadStatus.completed: return const Color(0xFF2ECC71);
      case DownloadStatus.failed: return const Color(0xFFE94560);
      case DownloadStatus.downloading: return const Color(0xFF4ECDC4);
      default: return Colors.white38;
    }
  }

  String get _statusLabel {
    switch (task.status) {
      case DownloadStatus.completed: return 'Terminé';
      case DownloadStatus.failed: return 'Échec';
      case DownloadStatus.downloading: return '${(task.progress * 100).toStringAsFixed(0)}%';
      default: return 'En attente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  task.audioOnly ? Icons.music_note : Icons.videocam,
                  color: _statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${task.format} • ${task.audioOnly ? "MP3" : "MP4"} • ${DateFormat('HH:mm').format(task.addedAt)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel,
                style: TextStyle(color: _statusColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              if (task.status == DownloadStatus.completed)
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 16, color: Color(0xFF2ECC71)),
                  onPressed: () => OpenFile.open(task.savedPath ?? ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else if (task.status == DownloadStatus.failed)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFE94560)),
                  onPressed: onRetry,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          // Progress bar
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: const Color(0xFF0F0F1A),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4ECDC4)),
                minHeight: 4,
              ),
            ),
          ],

          // Error message
          if (task.status == DownloadStatus.failed && task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: const TextStyle(color: Color(0xFFE94560), fontSize: 10),
            ),
          ],

          // URL preview
          const SizedBox(height: 4),
          Text(
            task.url,
            style: const TextStyle(color: Colors.white24, fontSize: 9),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
