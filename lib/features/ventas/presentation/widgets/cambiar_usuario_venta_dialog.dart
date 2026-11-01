import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../auth/data/usuario_model.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../../core/theme/app_colors.dart';

/// Pide documento + clave de OTRO usuario y, si son válidos, retorna su
/// UsuarioModel. Llama directo a AuthRepository.login (no a
/// AuthNotifier.login), así que valida contra Firestore igual que un login
/// normal pero sin tocar la sesión principal: no reemplaza authProvider.usuario
/// ni escribe nada en SharedPreferences.
Future<UsuarioModel?> mostrarCambiarUsuarioVentaDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<UsuarioModel>(
    useRootNavigator: false,
    context: context,
    barrierDismissible: false,
    builder: (context) => _CambiarUsuarioVentaDialog(ref: ref),
  );
}

class _CambiarUsuarioVentaDialog extends StatefulWidget {
  final WidgetRef ref;

  const _CambiarUsuarioVentaDialog({required this.ref});

  @override
  State<_CambiarUsuarioVentaDialog> createState() =>
      _CambiarUsuarioVentaDialogState();
}

class _CambiarUsuarioVentaDialogState
    extends State<_CambiarUsuarioVentaDialog> {
  final _documentoController = TextEditingController();
  final _claveController = TextEditingController();
  String? _error;
  bool _cargando = false;

  @override
  void dispose() {
    _documentoController.dispose();
    _claveController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final documento = _documentoController.text.trim();
    final clave = _claveController.text;
    if (documento.isEmpty || clave.isEmpty) {
      setState(() => _error = 'Ingresá el código de acceso y la clave');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuario = await widget.ref
          .read(authRepositoryProvider)
          .login(documento, clave);
      if (!mounted) return;
      Navigator.pop(context, usuario);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _cargando = false;
        _claveController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: esMovil ? tamano.width - 48 : 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.superficie,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.azulSuave2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    color: AppColors.azul3,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cambiar usuario de esta venta',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.texto,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Solo afecta esta venta, no la sesión: el resto del sistema sigue con tu usuario.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.gris600,
              ),
            ),
            const SizedBox(height: 18),
            CampoTecladoCompacto(
              controller: _documentoController,
              numerico: false,
              onSubmitted: (_) => _confirmar(),
              titulo: 'Código de acceso',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _documentoController,
                autofocus: true,
                onSubmitted: (_) => _confirmar(),
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Código de acceso',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.gris400,
                  ),
                  filled: true,
                  fillColor: AppColors.campo,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _claveController,
              obscureText: true,
              onSubmitted: (_) => _confirmar(),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Clave',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.gris400,
                ),
                errorText: _error,
                filled: true,
                fillColor: AppColors.campo,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cargando ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.texto,
                      side: BorderSide(color: AppColors.borde),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(fontSize: 13.5),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _cargando ? null : _confirmar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6FBD),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _cargando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Confirmar',
                            style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
