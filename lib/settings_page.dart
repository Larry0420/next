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
        ],
      ),
    );
  }
}

// Deprecated helper removed; use Kmb.getUseRouteApiSetting() instead.
