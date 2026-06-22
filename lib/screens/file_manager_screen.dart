import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  List<FileItem> _files = [];
  List<FileItem> _filteredFiles = [];
  bool _isScanning = false;
  double _scanProgress = 0;
  int _totalFiles = 0;
  String _currentPath = '';
  String _selectedFilter = 'Tous';
  Set<String> _selectedPaths = {};
  bool _selectionMode = false;
  String _searchQuery = '';
  String _sortBy = 'taille';
  Directory? _currentDirectory;

  final List<String> _filters = ['Tous', 'Images', 'Vidéos', 'Audios', 'Documents', 'APK', 'Gros fichiers'];

  final Map<String, List<String>> _extensionMap = {
    'Images': ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg'],
    'Vidéos': ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.3gp'],
    'Audios': ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus'],
    'Documents': ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv'],
    'APK': ['.apk'],
  };

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScan();
  }

  Future<void> _requestPermissionAndScan() async {
    if (Platform.isAndroid) {
      // Android 11+ : MANAGE_EXTERNAL_STORAGE via paramètres système
      if (await Permission.manageExternalStorage.isGranted) {
        await _scanFiles();
        return;
      }
      // Tenter d'abord les permissions media (Android 13+)
      final results = await [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      final anyGranted = results.values.any((s) => s.isGranted);
      if (!anyGranted) {
        // Demander MANAGE_EXTERNAL_STORAGE via paramètres
        await Permission.manageExternalStorage.request();
      }
    }
    await _scanFiles();
  }

  Future<void> _scanFiles() async {
    setState(() {
      _isScanning = true;
      _files = [];
      _scanProgress = 0;
      _currentPath = 'Démarrage du scan...';
    });

    List<FileItem> found = [];

    try {
      List<Directory> roots = [];

      if (Platform.isAndroid) {
        // Si MANAGE_EXTERNAL_STORAGE → scan complet, sinon dossiers accessibles
        final hasFullAccess = await Permission.manageExternalStorage.isGranted;
        if (hasFullAccess) {
          roots.add(Directory('/storage/emulated/0'));
        } else {
          // Dossiers accessibles sans permission spéciale
          for (final path in [
            '/storage/emulated/0/Download',
            '/storage/emulated/0/Downloads',
            '/storage/emulated/0/DCIM',
            '/storage/emulated/0/Pictures',
            '/storage/emulated/0/Movies',
            '/storage/emulated/0/Music',
            '/storage/emulated/0/Documents',
            '/storage/emulated/0/WhatsApp',
          ]) {
            final d = Directory(path);
            if (await d.exists()) roots.add(d);
          }
        }
      } else if (Platform.isWindows) {
        for (var drive in ['C:', 'D:', 'E:']) {
          final d = Directory(drive + r'\');
          if (await d.exists()) roots.add(d);
        }
      } else {
        final home = await getApplicationDocumentsDirectory();
        roots.add(home.parent);
      }

      for (final root in roots) {
        await _scanDirectory(root, found);
      }

      found.sort((a, b) => b.size.compareTo(a.size));

    } catch (e) {
      debugPrint('Erreur scan: $e');
    }

    setState(() {
      _isScanning = false;
      _files = found;
      _totalFiles = found.length;
      _applyFilter();
    });
  }

  Future<void> _scanDirectory(Directory dir, List<FileItem> found) async {
    try {
      final entities = dir.listSync(recursive: false, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            found.add(FileItem(
              path: entity.path,
              name: p.basename(entity.path),
              size: stat.size,
              extension: p.extension(entity.path).toLowerCase(),
              modifiedDate: stat.modified,
            ));
            if (found.length % 50 == 0) {
              setState(() {
                _currentPath = entity.path;
                _scanProgress = (found.length % 1000) / 1000;
              });
            }
          } catch (_) {}
        } else if (entity is Directory) {
          // Skip system dirs
          final name = p.basename(entity.path);
          if (!name.startsWith('.') && name != 'proc' && name != 'sys' && name != 'dev') {
            try {
              await _scanDirectory(entity, found);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  void _applyFilter() {
    List<FileItem> result = List.from(_files);

    // Filter by type
    if (_selectedFilter != 'Tous') {
      if (_selectedFilter == 'Gros fichiers') {
        result = result.where((f) => f.size > 50 * 1024 * 1024).toList(); // > 50MB
      } else {
        final exts = _extensionMap[_selectedFilter] ?? [];
        result = result.where((f) => exts.contains(f.extension)).toList();
      }
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      result = result.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // Sort
    if (_sortBy == 'taille') {
      result.sort((a, b) => b.size.compareTo(a.size));
    } else if (_sortBy == 'nom') {
      result.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortBy == 'date') {
      result.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    }

    setState(() => _filteredFiles = result);
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPaths.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Confirmer la suppression', style: TextStyle(color: Colors.white)),
        content: Text(
          'Supprimer $count fichier(s) ?\nCette action est irréversible.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    int deleted = 0;
    int freed = 0;
    for (final path in _selectedPaths) {
      try {
        final file = File(path);
        final item = _files.firstWhere((f) => f.path == path);
        freed += item.size;
        await file.delete();
        deleted++;
      } catch (_) {}
    }

    setState(() {
      _files.removeWhere((f) => _selectedPaths.contains(f.path));
      _selectedPaths.clear();
      _selectionMode = false;
      _applyFilter();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2ECC71),
          content: Text('$deleted fichier(s) supprimé(s) — ${_formatSize(freed)} libérés'),
        ),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int get _totalSize => _files.fold(0, (sum, f) => sum + f.size);
  int get _selectedSize => _files.where((f) => _selectedPaths.contains(f.path)).fold(0, (sum, f) => sum + f.size);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF16213E),
          child: Row(
            children: [
              _StatCard(
                label: 'Fichiers',
                value: _totalFiles.toString(),
                icon: Icons.insert_drive_file,
                color: const Color(0xFF4ECDC4),
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Total',
                value: _formatSize(_totalSize),
                icon: Icons.storage,
                color: const Color(0xFFFF6B35),
              ),
              if (_selectionMode) ...[
                const SizedBox(width: 10),
                _StatCard(
                  label: 'Sélectionnés',
                  value: _formatSize(_selectedSize),
                  icon: Icons.delete_sweep,
                  color: const Color(0xFFE94560),
                ),
              ],
            ],
          ),
        ),

        // Search + scan button
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un fichier...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) {
                    _searchQuery = v;
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Sort menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort, color: Colors.white70),
                color: const Color(0xFF1A1A2E),
                onSelected: (v) {
                  _sortBy = v;
                  _applyFilter();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'taille', child: Text('Par taille', style: TextStyle(color: Colors.white))),
                  const PopupMenuItem(value: 'nom', child: Text('Par nom', style: TextStyle(color: Colors.white))),
                  const PopupMenuItem(value: 'date', child: Text('Par date', style: TextStyle(color: Colors.white))),
                ],
              ),
              // Rescan
              IconButton(
                icon: _isScanning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE94560)))
                    : const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _isScanning ? null : _scanFiles,
              ),
            ],
          ),
        ),

        // Filter chips
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _filters.length,
            itemBuilder: (_, i) {
              final f = _filters[i];
              final isActive = _selectedFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    _selectedFilter = f;
                    _applyFilter();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: isActive ? const LinearGradient(colors: [Color(0xFFE94560), Color(0xFFFF6B35)]) : null,
                      color: isActive ? null : const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Scanning indicator
        if (_isScanning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  backgroundColor: const Color(0xFF1A1A2E),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFE94560)),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentPath,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],

        // File list
        Expanded(
          child: _filteredFiles.isEmpty && !_isScanning
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open, size: 60, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('Aucun fichier trouvé', style: TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredFiles.length,
                  itemBuilder: (_, i) {
                    final file = _filteredFiles[i];
                    final isSelected = _selectedPaths.contains(file.path);
                    return _FileListItem(
                      file: file,
                      isSelected: isSelected,
                      selectionMode: _selectionMode,
                      formatSize: _formatSize,
                      onTap: () {
                        if (_selectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedPaths.remove(file.path);
                              if (_selectedPaths.isEmpty) _selectionMode = false;
                            } else {
                              _selectedPaths.add(file.path);
                            }
                          });
                        } else {
                          OpenFile.open(file.path);
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          _selectionMode = true;
                          _selectedPaths.add(file.path);
                        });
                      },
                    );
                  },
                ),
        ),

        // Bottom action bar (selection mode)
        if (_selectionMode)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF16213E),
              border: Border(top: BorderSide(color: Color(0xFF2A2A4E))),
            ),
            child: Row(
              children: [
                Text(
                  '${_selectedPaths.length} fichier(s) sélectionné(s)',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedPaths.clear();
                    _selectionMode = false;
                  }),
                  child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: Text('Supprimer (${_formatSize(_selectedSize)})'),
                  onPressed: _deleteSelected,
                ),
              ],
            ),
          ),

        // Select All button
        if (!_selectionMode && _filteredFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectionMode = true;
                      _selectedPaths = _filteredFiles.map((f) => f.path).toSet();
                    });
                  },
                  icon: const Icon(Icons.select_all, size: 16),
                  label: const Text('Sélectionner tout'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class FileItem {
  final String path;
  final String name;
  final int size;
  final String extension;
  final DateTime modifiedDate;

  FileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.extension,
    required this.modifiedDate,
  });
}

class _FileListItem extends StatelessWidget {
  final FileItem file;
  final bool isSelected;
  final bool selectionMode;
  final String Function(int) formatSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileListItem({
    required this.file,
    required this.isSelected,
    required this.selectionMode,
    required this.formatSize,
    required this.onTap,
    required this.onLongPress,
  });

  IconData get _icon {
    final ext = file.extension;
    if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext)) return Icons.image;
    if (['.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp'].contains(ext)) return Icons.videocam;
    if (['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a'].contains(ext)) return Icons.music_note;
    if (['.pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['.doc', '.docx'].contains(ext)) return Icons.article;
    if (['.xls', '.xlsx'].contains(ext)) return Icons.table_chart;
    if (['.apk'].contains(ext)) return Icons.android;
    if (['.zip', '.rar', '.7z'].contains(ext)) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color get _iconColor {
    final ext = file.extension;
    if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext)) return const Color(0xFF4ECDC4);
    if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) return const Color(0xFFE94560);
    if (['.mp3', '.wav', '.flac', '.aac'].contains(ext)) return const Color(0xFFFF6B35);
    if (['.pdf'].contains(ext)) return const Color(0xFFE74C3C);
    if (['.apk'].contains(ext)) return const Color(0xFF2ECC71);
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE94560).withOpacity(0.15) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFE94560) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFE94560) : Colors.white38,
                  size: 22,
                ),
              ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_icon, color: _iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.path,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatSize(file.size),
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yy').format(file.modifiedDate),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
