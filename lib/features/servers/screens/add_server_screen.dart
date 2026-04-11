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
import '../../../ssh/ssh_credential.dart';
import '../../../ssh/ssh_key_installer_service.dart';
import '../../../ssh/ssh_key_service.dart';

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
  final _privateKeyPassphraseController = TextEditingController();

  AuthType _authType = AuthType.password;
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isGeneratingKey = false;
  bool _isInstallingKey = false;
  bool _isIconPickerExpanded = false;
  Color _selectedColor = OrbitalColors.accent;
  String _selectedIconKey = ServerIconCatalog.defaultKey;
  bool _keyInstallStatusIsSuccess = false;
  String? _keyInstallStatusMessage;
  String? _privateKeyValidationError;
  PrivateKeyCredential? _privateKeyCredential;
  PrivateKeySource _privateKeySource = PrivateKeySource.manual;
  GeneratedKeyAlgorithm? _privateKeyAlgorithm;
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
    _privateKeyPassphraseController.dispose();
    super.dispose();
  }

  // ── Test connection ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate() || !_validatePrivateKeySelection()) {
      return;
    }

    setState(() => _testResult = _TestResult.testing);

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text) ?? 22;
    final username = _usernameController.text.trim();
    final keyService = ref.read(sshKeyServiceProvider);

    SSHClient? client;
    final stopwatch = Stopwatch()..start();

    try {
      final credential = _buildCredential();
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      client = keyService.createClient(
        socket: socket,
        username: username,
        credential: credential,
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
    if (!_formKey.currentState!.validate() || !_validatePrivateKeySelection()) {
      return;
    }
    setState(() => _isSaving = true);

    try {
      final repo = ref.read(serverRepositoryProvider);
      final host = _hostController.text.trim();
      final username = _usernameController.text.trim();
      final credential = _buildCredential();

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

  SshCredential _buildCredential() {
    if (_authType == AuthType.password) {
      return PasswordCredential(password: _passwordController.text);
    }

    if (_privateKeyCredential != null) {
      return _privateKeyCredential!;
    }

    return ref
        .read(sshKeyServiceProvider)
        .analyzePrivateKey(
          _privateKeyController.text,
          source: _privateKeySource,
          passphrase: _privateKeyPassphraseController.text,
          algorithm: _privateKeyAlgorithm,
        );
  }

  bool _validatePrivateKeySelection() {
    if (_authType != AuthType.privateKey) return true;

    try {
      _buildCredential();
      if (_privateKeyValidationError != null) {
        setState(() => _privateKeyValidationError = null);
      }
      return true;
    } on SshKeyValidationException catch (e) {
      setState(() => _privateKeyValidationError = e.message);
      return false;
    }
  }

  Future<void> _importPrivateKeyFromFile() async {
    try {
      final file = await ref.read(documentPickerServiceProvider).pickTextFile();
      if (file == null) return;
      await _applyPrivateKeyInput(file.content, source: PrivateKeySource.file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to import key: $e')));
    }
  }

  Future<void> _pastePrivateKeyFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }

    await _applyPrivateKeyInput(text, source: PrivateKeySource.clipboard);
  }

  Future<void> _generatePrivateKey() async {
    final algorithm = await _pickGeneratedKeyAlgorithm();
    if (algorithm == null) return;

    setState(() => _isGeneratingKey = true);
    try {
      final credential = await ref
          .read(sshKeyServiceProvider)
          .generateKey(algorithm: algorithm);
      if (!mounted) return;

      setState(() {
        _privateKeyController.text = credential.pem;
        _privateKeyPassphraseController.clear();
        _privateKeyCredential = credential;
        _keyInstallStatusMessage = null;
        _keyInstallStatusIsSuccess = false;
        _privateKeyValidationError = null;
        _privateKeySource = PrivateKeySource.generated;
        _privateKeyAlgorithm = algorithm;
        _testResult = _TestResult.idle;
      });

      await _showPublicKeySheet(credential);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate key: $e')));
    } finally {
      if (mounted) {
        setState(() => _isGeneratingKey = false);
      }
    }
  }

  Future<void> _applyPrivateKeyInput(
    String pem, {
    required PrivateKeySource source,
    GeneratedKeyAlgorithm? algorithm,
  }) async {
    final keyService = ref.read(sshKeyServiceProvider);
    _privateKeySource = source;
    _privateKeyAlgorithm = algorithm;
    _privateKeyController.text = pem.trim();
    _privateKeyPassphraseController.clear();

    if (keyService.isEncryptedPem(_privateKeyController.text) &&
        _privateKeyPassphraseController.text.isEmpty) {
      final passphrase = await _promptForPassphrase();
      if (passphrase != null) {
        _privateKeyPassphraseController.text = passphrase;
      }
    }

    try {
      final credential = keyService.analyzePrivateKey(
        _privateKeyController.text,
        source: _privateKeySource,
        passphrase: _privateKeyPassphraseController.text,
        algorithm: _privateKeyAlgorithm,
      );
      if (!mounted) return;
      setState(() {
        _privateKeyCredential = credential;
        _keyInstallStatusMessage = null;
        _keyInstallStatusIsSuccess = false;
        _privateKeyValidationError = null;
        _testResult = _TestResult.idle;
      });
    } on SshKeyValidationException catch (e) {
      _privateKeyController.clear();
      _privateKeyPassphraseController.clear();
      if (!mounted) return;
      setState(() {
        _privateKeyCredential = null;
        _keyInstallStatusMessage = null;
        _keyInstallStatusIsSuccess = false;
        _privateKeyValidationError = e.message;
        _testResult = _TestResult.idle;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import key: ${e.message}')),
      );
    }
  }

  Future<String?> _promptForPassphrase() async {
    var passphrase = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Private Key Passphrase'),
          content: TextFormField(
            autofocus: true,
            obscureText: true,
            onChanged: (value) => passphrase = value,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              hintText: 'Enter the key passphrase',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(passphrase),
              child: const Text('Use Passphrase'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<GeneratedKeyAlgorithm?> _pickGeneratedKeyAlgorithm() {
    return showModalBottomSheet<GeneratedKeyAlgorithm>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bolt_rounded),
                title: const Text('Ed25519'),
                subtitle: const Text('Modern default with compact keys'),
                onTap: () =>
                    Navigator.of(context).pop(GeneratedKeyAlgorithm.ed25519),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('RSA 4096'),
                subtitle: const Text(
                  'Larger key for older server compatibility',
                ),
                onTap: () =>
                    Navigator.of(context).pop(GeneratedKeyAlgorithm.rsa4096),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _validateInstallFields() {
    if (_hostController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Host is required')));
      return false;
    }

    if (_usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Username is required')));
      return false;
    }

    if (int.tryParse(_portController.text.trim()) == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Valid port is required')));
      return false;
    }

    return true;
  }

  Future<String?> _promptForInstallPassword() async {
    var password = _passwordController.text;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Install Key on Server'),
          content: TextFormField(
            initialValue: password,
            autofocus: true,
            obscureText: true,
            onChanged: (value) => password = value,
            decoration: const InputDecoration(
              labelText: 'Server Password',
              hintText: 'Used one time to install the public key',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(password),
              child: const Text('Install Key'),
            ),
          ],
        );
      },
    );
    return result?.trim();
  }

  Future<void> _installKeyOnServer(PrivateKeyCredential credential) async {
    if (!_validateInstallFields()) return;

    final password = await _promptForInstallPassword();
    if (password == null) return;
    if (password.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password is required to install the key'),
        ),
      );
      return;
    }

    setState(() {
      _isInstallingKey = true;
      _keyInstallStatusMessage = null;
      _keyInstallStatusIsSuccess = false;
    });

    try {
      final result = await ref
          .read(sshKeyInstallerServiceProvider)
          .installPublicKey(
            host: _hostController.text.trim(),
            port: int.parse(_portController.text.trim()),
            username: _usernameController.text.trim(),
            passwordCredential: PasswordCredential(password: password),
            privateKeyCredential: credential,
          );

      if (!mounted) return;
      final message = result.alreadyPresent
          ? 'Key already present on the server. Save to keep using SSH key auth.'
          : 'Key installed on the server. Save to keep using SSH key auth.';
      setState(() {
        _authType = AuthType.privateKey;
        _passwordController.clear();
        _keyInstallStatusMessage = message;
        _keyInstallStatusIsSuccess = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on SshKeyInstallException catch (e) {
      if (!mounted) return;
      setState(() {
        _keyInstallStatusMessage = e.message;
        _keyInstallStatusIsSuccess = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _isInstallingKey = false);
      }
    }
  }

  Future<void> _showPublicKeySheet(PrivateKeyCredential credential) async {
    final publicKey = credential.publicKey;
    if (publicKey == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public Key',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add this public key to ~/.ssh/authorized_keys on the server.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(publicKey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _copyPublicKey(publicKey);
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy Public Key'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyPublicKey(String publicKey) async {
    await Clipboard.setData(ClipboardData(text: publicKey));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Public key copied')));
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
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: Theme.of(context).brightness == Brightness.dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
          'Icon Color',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _serverColors.map((color) {
            final isSelected = color.toARGB32() == _selectedColor.toARGB32();
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
                            color: color.withValues(alpha: 0.5),
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
    final selectedOption = ServerIconCatalog.options.firstWhere(
      (option) => option.key == _selectedIconKey,
      orElse: () => ServerIconCatalog.options.first,
    );
    final icon = selectedOption.icon;
    final label = _nameController.text.trim().isEmpty
        ? 'Server Preview'
        : _nameController.text.trim();
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Icon Selection',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () =>
              setState(() => _isIconPickerExpanded = !_isIconPickerExpanded),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
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
                Icon(
                  _isIconPickerExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _isIconPickerExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ServerIconCatalog.options.map((option) {
                      final isSelected = option.key == _selectedIconKey;

                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedIconKey = option.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withValues(alpha: 0.14)
                                : Theme.of(
                                    context,
                                  ).inputDecorationTheme.fillColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? color.withValues(alpha: 0.4)
                                  : borderColor,
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
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                option.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox.shrink(),
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
    int maxLines = 1,
    int? minLines,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
      maxLines: obscureText ? 1 : maxLines,
      minLines: obscureText ? 1 : minLines,
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
          if (type == AuthType.privateKey &&
              _privateKeyController.text.isEmpty) {
            _privateKeySource = PrivateKeySource.manual;
            _privateKeyAlgorithm = null;
            _privateKeyCredential = null;
          }
          _keyInstallStatusMessage = null;
          _keyInstallStatusIsSuccess = false;
          _privateKeyValidationError = null;
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

  Widget _buildSshActionButton({
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
    bool emphasized = false,
  }) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    final backgroundAlpha = switch ((theme.brightness, emphasized)) {
      (Brightness.dark, true) => 0.18,
      (Brightness.dark, false) => 0.12,
      (Brightness.light, true) => 0.12,
      (Brightness.light, false) => 0.07,
    };
    final borderAlpha = emphasized ? 0.34 : 0.2;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: tint,
        backgroundColor: tint.withValues(alpha: backgroundAlpha),
        disabledBackgroundColor: theme.inputDecorationTheme.fillColor,
        disabledForegroundColor: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: 0.7,
        ),
        side: BorderSide(color: tint.withValues(alpha: borderAlpha)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPrivateKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildSshActionButton(
              onPressed: _importPrivateKeyFromFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: 'Import File',
            ),
            _buildSshActionButton(
              onPressed: _pastePrivateKeyFromClipboard,
              icon: const Icon(Icons.content_paste_rounded),
              label: 'Paste Clipboard',
            ),
            _buildSshActionButton(
              onPressed: _isGeneratingKey ? null : _generatePrivateKey,
              emphasized: true,
              icon: _isGeneratingKey
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: _isGeneratingKey ? 'Generating…' : 'Generate Key',
            ),
          ],
        ),
        if (_privateKeyValidationError != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _privateKeyValidationError!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
        if (_privateKeyCredential != null) ...[
          const SizedBox(height: 12),
          _buildPrivateKeySummary(_privateKeyCredential!),
        ] else ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Import, paste, or generate an SSH key to continue.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPrivateKeySummary(PrivateKeyCredential credential) {
    final metadata = <String>[
      'Source: ${switch (credential.source) {
        PrivateKeySource.manual => 'Manual',
        PrivateKeySource.clipboard => 'Clipboard',
        PrivateKeySource.file => 'File import',
        PrivateKeySource.generated => 'Generated',
      }}',
      if (credential.algorithm != null)
        'Algorithm: ${credential.algorithm == GeneratedKeyAlgorithm.ed25519 ? 'Ed25519' : 'RSA 4096'}',
      if (credential.fingerprint != null)
        'Fingerprint: ${credential.fingerprint}',
      if (credential.hasPassphrase) 'Passphrase saved',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key Ready',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in metadata)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (credential.publicKey != null)
                _buildSshActionButton(
                  onPressed: () => _showPublicKeySheet(credential),
                  icon: const Icon(Icons.visibility_rounded),
                  label: 'View Public Key',
                ),
              if (credential.publicKey != null)
                _buildSshActionButton(
                  onPressed: () => _copyPublicKey(credential.publicKey!),
                  icon: const Icon(Icons.copy_rounded),
                  label: 'Copy Public Key',
                ),
              _buildSshActionButton(
                onPressed: _isInstallingKey
                    ? null
                    : () => _installKeyOnServer(credential),
                emphasized: true,
                icon: _isInstallingKey
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: _isInstallingKey
                    ? 'Installing…'
                    : 'Install Key on Server',
              ),
            ],
          ),
          if (_keyInstallStatusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _keyInstallStatusMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _keyInstallStatusIsSuccess
                    ? OrbitalColors.online
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
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
