import 'package:flutter/material.dart';
import 'audio_device_service.dart';

/// Vista de diagnóstico de dispositivos de audio.
/// Accesible desde el FAB en la HomePage.
/// Optimizada para Windows y macOS.
class AudioDevicesPage extends StatefulWidget {
  const AudioDevicesPage({super.key});

  @override
  State<AudioDevicesPage> createState() => _AudioDevicesPageState();
}

class _AudioDevicesPageState extends State<AudioDevicesPage> {
  final AudioDeviceService _svc = AudioDeviceService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    // Enumera automáticamente al abrir
    WidgetsBinding.instance.addPostFrameCallback((_) => _svc.enumerateDevices());
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    // Detiene el test si el usuario cierra la pantalla
    _svc.stopMicTest();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _refresh() => _svc.enumerateDevices();

  Future<void> _toggleMicTest() async {
    if (_svc.isTesting) {
      await _svc.stopMicTest();
    } else {
      await _svc.startMicTest(deviceId: _svc.selectedInput?.deviceId);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Dispositivos de Audio'),
        centerTitle: false,
        actions: [
          // Botón refrescar
          Tooltip(
            message: 'Actualizar dispositivos',
            child: IconButton(
              icon: _svc.isEnumerating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: _svc.isEnumerating ? null : _refresh,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _svc.isEnumerating && _svc.devices.isEmpty
          ? _buildLoading(cs)
          : _buildContent(theme, cs),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading(ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text('Detectando dispositivos...',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );

  // ── Contenido principal ───────────────────────────────────────────────────

  Widget _buildContent(ThemeData theme, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Error global de enumeración ────────────────────────────────
        if (_svc.enumerateError != null) ...[
          _ErrorBanner(message: _svc.enumerateError!, onRetry: _refresh),
          const SizedBox(height: 16),
        ],

        // ── Resumen de estado ──────────────────────────────────────────
        _StatusSummaryCard(svc: _svc),
        const SizedBox(height: 20),

        // ── Micrófonos (entradas) ──────────────────────────────────────
        _SectionHeader(
          icon: Icons.mic_rounded,
          title: 'Micrófonos',
          count: _svc.inputs.length,
          color: cs.primary,
        ),
        const SizedBox(height: 8),
        if (_svc.inputs.isEmpty)
          _EmptyDeviceCard(
            message: 'No se detectaron micrófonos.',
            suggestion: 'Conecta un micrófono USB o auriculares con micrófono.',
          )
        else
          ..._svc.inputs.map((d) => _DeviceCard(
                device: d,
                isSelected: _svc.selectedInput?.deviceId == d.deviceId,
                onSelect: () => _svc.selectInput(d),
              )),

        const SizedBox(height: 20),

        // ── Altavoces / Auriculares (salidas) ──────────────────────────
        _SectionHeader(
          icon: Icons.headphones_rounded,
          title: 'Altavoces / Auriculares',
          count: _svc.outputs.length,
          color: cs.secondary,
        ),
        const SizedBox(height: 8),
        if (_svc.outputs.isEmpty)
          _EmptyDeviceCard(
            message: 'No se detectaron dispositivos de salida.',
            suggestion: 'Conecta auriculares o verifica el volumen del sistema.',
          )
        else
          ..._svc.outputs.map((d) => _DeviceCard(
                device: d,
                isSelected: _svc.selectedOutput?.deviceId == d.deviceId,
                onSelect: () => _svc.selectOutput(d),
              )),

        const SizedBox(height: 24),

        // ── Panel de prueba de micrófono ───────────────────────────────
        _MicTestPanel(
          svc: _svc,
          onToggle: _toggleMicTest,
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Resumen de estado ──────────────────────────────────────────────────────

class _StatusSummaryCard extends StatelessWidget {
  final AudioDeviceService svc;
  const _StatusSummaryCard({required this.svc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = svc.hasInputDevice;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ok
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ok
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: ok ? Colors.green : Colors.orange,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? 'Sistema de audio listo' : 'Sin dispositivos de entrada',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: ok ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ok
                      ? '${svc.inputs.length} micrófono(s) · ${svc.outputs.length} salida(s) detectada(s)'
                      : 'Las llamadas no funcionarán sin micrófono',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Encabezado de sección ──────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Card de dispositivo ────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final AudioDevice device;
  final bool isSelected;
  final VoidCallback onSelect;

  const _DeviceCard({
    required this.device,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.5)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? cs.primary.withValues(alpha: 0.6)
                    : cs.outline.withValues(alpha: 0.2),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Ícono del dispositivo
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.12)
                        : cs.onSurface.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    device.kind.icon,
                    size: 20,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                // Info del dispositivo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? cs.primary : cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (device.deviceId.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'ID: ${device.deviceId.length > 20 ? '${device.deviceId.substring(0, 20)}…' : device.deviceId}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Indicador seleccionado
                if (isSelected)
                  Icon(Icons.radio_button_checked_rounded,
                      color: cs.primary, size: 20)
                else
                  Icon(Icons.radio_button_unchecked_rounded,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card vacía ─────────────────────────────────────────────────────────────

class _EmptyDeviceCard extends StatelessWidget {
  final String message;
  final String suggestion;

  const _EmptyDeviceCard({required this.message, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: cs.error.withValues(alpha: 0.7), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.error,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(suggestion,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Panel de prueba de micrófono ───────────────────────────────────────────

class _MicTestPanel extends StatelessWidget {
  final AudioDeviceService svc;
  final VoidCallback onToggle;

  const _MicTestPanel({required this.svc, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTesting = svc.isTesting;
    final isRequesting = svc.micTestStatus == MicTestStatus.requesting;
    final hasFailed = svc.micTestStatus == MicTestStatus.failed;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado del panel ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Icons.science_rounded, color: cs.tertiary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Prueba de Micrófono',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: cs.tertiary,
                  ),
                ),
                const Spacer(),
                if (svc.selectedInput != null)
                  Flexible(
                    child: Chip(
                      label: Text(
                        svc.selectedInput!.displayLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      avatar: Icon(Icons.mic_rounded,
                          size: 14, color: cs.primary),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Indicador de nivel ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MicLevelIndicator(
              level: svc.micLevel,
              isActive: isTesting,
              status: svc.micTestStatus,
            ),
          ),

          const SizedBox(height: 16),

          // ── Mensaje de error ──────────────────────────────────────
          if (hasFailed && svc.micTestError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: cs.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        svc.micTestError!,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.error,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Botón iniciar / detener ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: isRequesting
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: const Text('Solicitando acceso…'),
                    )
                  : isTesting
                      ? FilledButton.icon(
                          onPressed: onToggle,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Detener prueba'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: svc.hasInputDevice ? onToggle : null,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Iniciar prueba de micrófono'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
            ),
          ),

          // ── Nota informativa ──────────────────────────────────────
          if (isTesting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                '🎤 Habla cerca del micrófono — el indicador debe moverse.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Indicador visual de nivel de micrófono ────────────────────────────────

class _MicLevelIndicator extends StatelessWidget {
  final double level;
  final bool isActive;
  final MicTestStatus status;

  const _MicLevelIndicator({
    required this.level,
    required this.isActive,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Estado visual según el status
    final (Color barColor, String label, IconData icon) = switch (status) {
      MicTestStatus.idle => (cs.outline, 'Sin prueba activa', Icons.mic_none_rounded),
      MicTestStatus.requesting => (Colors.orange, 'Solicitando acceso…', Icons.hourglass_top_rounded),
      MicTestStatus.recording => (Colors.green, 'Capturando audio…', Icons.graphic_eq_rounded),
      MicTestStatus.success => (Colors.green, 'Capturando audio…', Icons.graphic_eq_rounded),
      MicTestStatus.failed => (cs.error, 'Error al acceder al micrófono', Icons.mic_off_rounded),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label de estado
        Row(
          children: [
            Icon(icon, color: barColor, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: barColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Barras de nivel (estilo ecualizador)
        SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(28, (i) {
              // Calcula la altura de cada barra con offset senoidal
              final normalizedPos = i / 28;
              final barLevel = isActive
                  ? (level * (0.4 + 0.6 * _wave(normalizedPos, level)))
                      .clamp(0.02, 1.0)
                  : 0.04;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    curve: Curves.easeOut,
                    height: 48 * barLevel,
                    decoration: BoxDecoration(
                      color: isActive
                          ? barColor.withValues(
                              alpha: 0.4 + 0.6 * barLevel)
                          : cs.outline.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 8),

        // Barra de progreso lineal
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: isActive ? level : 0.0,
            backgroundColor: cs.outline.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              isActive ? barColor : cs.outline,
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  double _wave(double pos, double level) {
    final center = 0.5;
    final distance = (pos - center).abs();
    return 1.0 - distance * 1.4 * (1.0 - level * 0.5);
  }
}

// ── Banner de error ────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

