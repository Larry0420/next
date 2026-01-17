import 'package:flutter/material.dart';
import 'kmb.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _useRouteApi = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await Kmb.getUseRouteApiSetting();
    setState(() { _useRouteApi = v; });
  }

  Future<void> _set(bool v) async {
    await Kmb.setUseRouteApiSetting(v);
    setState(() { _useRouteApi = v; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Always use per-route API for route stops'),
            subtitle: Text('Fetch fresh route-stop data from the route API every time when enabled.'),
            value: _useRouteApi,
            onChanged: _set,
          ),
          ListTile(
            title: Text('Regenerate prebuilt data'),
            subtitle: Text('Fetch route & stop data and store in app documents (prebuilt).'),
            trailing: Icon(Icons.refresh),
            onTap: () async {
              // show progress dialog
              showDialog<void>(context: context, barrierDismissible: false, builder: (ctx) {
                return const Center(child: CircularProgressIndicator(year2023: false,));
              });
              final result = await Kmb.writePrebuiltAssetsToDocuments();
              // dismiss dialog
              if (mounted && Navigator.canPop(context)) Navigator.pop(context);
              if (mounted) {
                if (result.ok) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prebuilt data regenerated')));
                } else {
                  final useBundled = await showDialog<bool>(context: context, builder: (ctx) {
                    return AlertDialog(
                      title: const Text('Regeneration failed'),
                      content: Text('Failed to regenerate prebuilt data:\n${result.error}\n\nWould you like to use the bundled prebuilt assets instead?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
                      ],
                    );
                  });
                  if (useBundled == true) {
                    // show progress
                    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(year2023: false,)));
                    final copyRes = await Kmb.copyBundledPrebuiltToDocuments();
                    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copyRes.ok ? 'Bundled assets copied' : 'Failed to copy bundled assets: ${copyRes.error}')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Regeneration failed: ${result.error}')));
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// Deprecated helper removed; use Kmb.getUseRouteApiSetting() instead.
