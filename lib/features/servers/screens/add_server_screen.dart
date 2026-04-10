import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/server_icon_catalog.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/tables.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';

// ── Test result state ─────────────────────────────────────────────────────────

enum _TestStatus { idle, testing, success, failure }

class _TestResult {
  final _TestStatus status;
  final String? message; // error message or latency string
  const _TestResult(this.status, [this.message]);
  static const idle = _TestResult(_TestStatus.idle);
  static const testing = _TestResult(_TestStatus.testing);
}

// ── AddServerScreen ───────────────────────────────────────────────────────────

class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();

  AuthType _authType = AuthType.password;
  bool _obscurePassword = true;
  bool _isSaving = false;
  Color _selectedColor = OrbitalColors.accent;
  String _selectedIconKey = ServerIconCatalog.defaultKey;
  _TestResult _testResult = _TestResult.idle;

  final List<Color> _serverColors = const [
    OrbitalColors.accent,
    OrbitalColors.memory,
    OrbitalColors.network,
    OrbitalColors.warning,
    OrbitalColors.danger,
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF84CC16),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  // ── Test connection ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _testResult = _TestResult.testing);

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text) ?? 22;
    final username = _usernameController.text.trim();
    final credential = _authType == AuthType.password
        ? _passwordController.text
        : _privateKeyController.text;

    SSHClient? client;
    final stopwatch = Stopwatch()..start();

    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: _authType == AuthType.password
            ? () => credential
            : null,
        identities: _authType == AuthType.privateKey
            ? [...SSHKeyPair.fromPem(credential)]
            : null,
      );

      await client.authenticated;
      stopwatch.stop();

      // Run a quick smoke-test command to confirm the shell works.
      final session = await client.execute('echo ok');
      await session.done;

      if (!mounted) return;
      setState(
        () => _testResult = _TestResult(
          _TestStatus.success,
          '${stopwatch.elapsedMilliseconds} ms',
        ),
      );
    } on SSHAuthError catch (e) {
      if (!mounted) return;
      setState(
        () => _testResult = _TestResult(
          _TestStatus.failure,
          'Auth failed: ${e.message}',
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _testResult = const _TestResult(
          _TestStatus.failure,
          'Connection timed out',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Trim noisy dart:io prefix from socket errors
      final msg = e.toString().replaceFirst('SocketException: ', '');
      setState(() => _testResult = _TestResult(_TestStatus.failure, msg));
    } finally {
      client?.close();
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repo = ref.read(serverRepositoryProvider);
      final host = _hostController.text.trim();
      final username = _usernameController.text.trim();
      final credential = _authType == AuthType.password
          ? _passwordController.text
          : _privateKeyController.text;

      final credentialKey = repo.generateCredentialKey(host, username);

      await repo.addServer(
        ServerFormData(
          name: _nameController.text.trim(),
          host: host,
          port: int.parse(_portController.text),
          username: username,
          authType: _authType,
          credentialStorageKey: credentialKey,
          color: _selectedColor,
          iconKey: _selectedIconKey,
        ),
        credential,
      );

      if (!mounted) return;
      context.pop();
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Add Server',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => context.pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Text(
                      'Save',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              title: 'Identity',
              children: [
                _buildIdentityPreview(),
                const SizedBox(height: 16),
                _buildColorPicker(),
                const SizedBox(height: 16),
                _buildIconPicker(),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameController,
                  label: 'Display Name',
                  hint: 'e.g. Production Web Server',
                  icon: Icons.label_outline_rounded,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Name is required' : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'Connection',
              children: [
                _buildTextField(
                  controller: _hostController,
                  label: 'Host',
                  hint: 'e.g. 192.168.1.1 or server.example.com',
                  icon: Icons.dns_outlined,
                  keyboardType: TextInputType.url,
                  // Clear stale test result when host changes
                  onChanged: (_) =>
                      setState(() => _testResult = _TestResult.idle),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Host is required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        controller: _usernameController,
                        label: 'Username',
                        hint: 'e.g. root',
                        icon: Icons.person_outline_rounded,
                        onChanged: (_) =>
                            setState(() => _testResult = _TestResult.idle),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _portController,
                        label: 'Port',
                        hint: '22',
                        icon: Icons.settings_ethernet_rounded,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) =>
                            setState(() => _testResult = _TestResult.idle),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final port = int.tryParse(v);
                          if (port == null || port < 1 || port > 65535) {
                            return 'Invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'Authentication',
              children: [
                _buildAuthTypeToggle(),
                const SizedBox(height: 16),
                if (_authType == AuthType.password) _buildPasswordField(),
                if (_authType == AuthType.privateKey) _buildPrivateKeyField(),
              ],
            ),
            const SizedBox(height: 24),
            _buildTestConnectionButton(),
            // Inline result card — animated in/out
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _testResult.status != _TestStatus.idle
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _TestResultCard(result: _testResult),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildTestConnectionButton() {
    final isTesting = _testResult.status == _TestStatus.testing;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isTesting ? null : _testConnection,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isTesting)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.wifi_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Text(
                  isTesting ? 'Testing…' : 'Test Connection',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
            ),
            boxShadow: Theme.of(context).brightness == Brightness.dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server Color',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _serverColors.map((color) {
            final isSelected = color.value == _selectedColor.value;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildIdentityPreview() {
    final color = _selectedColor;
    final icon = ServerIconCatalog.resolveIcon(_selectedIconKey);
    final label = _nameController.text.trim().isEmpty
        ? 'Server Preview'
        : _nameController.text.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server Icon',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ServerIconCatalog.options.map((option) {
            final isSelected = option.key == _selectedIconKey;
            final color = _selectedColor;

            return GestureDetector(
              onTap: () => setState(() => _selectedIconKey = option.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.14)
                      : Theme.of(context).inputDecorationTheme.fillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? color.withOpacity(0.4)
                        : Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option.icon,
                      size: 18,
                      color: isSelected
                          ? color
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }

  Widget _buildAuthTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildAuthTab(
            'Password',
            AuthType.password,
            Icons.lock_outline_rounded,
          ),
          _buildAuthTab('SSH Key', AuthType.privateKey, Icons.vpn_key_outlined),
        ],
      ),
    );
  }

  Widget _buildAuthTab(String label, AuthType type, IconData icon) {
    final isSelected = _authType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _authType = type;
          _testResult = _TestResult.idle;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return _buildTextField(
      controller: _passwordController,
      label: 'Password',
      hint: 'SSH password',
      icon: Icons.password_rounded,
      obscureText: _obscurePassword,
      onChanged: (_) => setState(() => _testResult = _TestResult.idle),
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
    );
  }

  Widget _buildPrivateKeyField() {
    return _buildTextField(
      controller: _privateKeyController,
      label: 'Private Key (PEM)',
      hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
      icon: Icons.key_rounded,
      onChanged: (_) => setState(() => _testResult = _TestResult.idle),
      validator: (v) =>
          v == null || v.isEmpty ? 'Private key is required' : null,
    );
  }
}

// ── _TestResultCard ───────────────────────────────────────────────────────────

class _TestResultCard extends StatelessWidget {
  final _TestResult result;

  const _TestResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status == _TestStatus.success;
    final isTesting = result.status == _TestStatus.testing;

    final color = isTesting
        ? Theme.of(context).colorScheme.primary
        : isSuccess
        ? OrbitalColors.online
        : OrbitalColors.danger;

    final icon = isTesting
        ? Icons.wifi_rounded
        : isSuccess
        ? Icons.check_circle_rounded
        : Icons.error_rounded;

    final title = isTesting
        ? 'Connecting…'
        : isSuccess
        ? 'Connection successful'
        : 'Connection failed';

    final subtitle = isTesting
        ? 'Attempting SSH handshake'
        : isSuccess
        ? 'Round-trip: ${result.message}'
        : result.message ?? 'Unknown error';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Menlo',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
