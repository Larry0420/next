import 'package:flutter/material.dart';
import '../kmb.dart';
import 'dart:convert';

/// Page that lists saved request files, allows preview, restore and delete.
class SavedFilesPage extends StatefulWidget {
  const SavedFilesPage({Key? key}) : super(key: key);

  @override
  State<SavedFilesPage> createState() => _SavedFilesPageState();
}

class _SavedFilesPageState extends State<SavedFilesPage> {
  List<String> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final files = await Kmb.listSavedRequestFiles();
      setState(() { _files = files; });
    } catch (_) {
      setState(() { _files = []; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _previewFile(String filename) async {
    // filename likely contains extension (e.g., name.json)
    if (filename.toLowerCase().endsWith('.json')) {
      final bare = filename.substring(0, filename.length - '.json'.length);
      final data = await Kmb.loadRequestJsonFromFile(bare);
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await showDialog(context: context, builder: (_) => AlertDialog(
        title: Text(filename),
        content: SingleChildScrollView(child: SelectableText(pretty)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close')),
          TextButton(onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop(data); // return data as restore result
          }, child: Text('Restore')),
        ],
      ));
    } else {
      // unsupported compressed file preview
      await showDialog(context: context, builder: (_) => AlertDialog(
        title: Text('Preview not supported'),
        content: Text('Preview for this file type is not supported in-app.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close'))],
      ));
    }
    // after preview, refresh list in case a restore action deleted/changed files elsewhere
    await _refresh();
  }

  Future<void> _deleteFile(String filename) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Delete file?'),
      content: Text('Delete $filename? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true) {
      final deleted = await Kmb.deleteSavedRequestFile(filename);
      if (deleted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $filename')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete $filename')));
      }
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Saved requests')),
      body: _loading
        ? Center(child: CircularProgressIndicator(year2023: false,))
        : _files.isEmpty
          ? Center(child: Text('No saved files'))
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, idx) {
                final name = _files[idx];
                return ListTile(
                  title: Text(name),
                  onTap: () => _previewFile(name),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_forever, color: Colors.redAccent),
                    onPressed: () => _deleteFile(name),
                  ),
                );
              },
            ),
    );
  }
}
