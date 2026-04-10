import 'package:flutter/material.dart';

class ServerDetailScreen extends StatelessWidget {
  final String serverId;
  const ServerDetailScreen({super.key, required this.serverId});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text('Server $serverId')),
      );
}
