import 'package:flutter/material.dart';

class SubModulo {
  final String titulo;
  final IconData icono;
  final String moduleKey;
  final bool soloAdmin;

  SubModulo({
    required this.titulo,
    required this.icono,
    required this.moduleKey,
    this.soloAdmin = false,
  });
}

class ModuloMenu {
  final String titulo;
  final IconData icono;
  final Color color;
  final List<SubModulo> subModulos;

  ModuloMenu({
    required this.titulo,
    required this.icono,
    required this.color,
    required this.subModulos,
  });
}

List<ModuloMenu> obtenerModulos() {
  return [
    ModuloMenu(
      titulo: 'Usuarios',
      icono: Icons.people_alt_outlined,
      color: const Color(0xFFC62828),
      subModulos: [
        SubModulo(titulo: 'Usuarios', icono: Icons.people_alt_outlined, moduleKey: 'usuarios', soloAdmin: true),
      ],
    ),
    ModuloMenu(
      titulo: 'Mantenedor',
      icono: Icons.settings_outlined,
      color: const Color(0xFF0EA5A4),
      subModulos: [
        SubModulo(titulo: 'Categorías', icono: Icons.category_outlined, moduleKey: 'categorias', soloAdmin: true),
        SubModulo(titulo: 'Inventario', icono: Icons.inventory_2_outlined, moduleKey: 'inventario', soloAdmin: true),
        SubModulo(titulo: 'Auditoría de Inventario', icono: Icons.fact_check_outlined, moduleKey: 'auditoria_inventario', soloAdmin: true),
        SubModulo(titulo: 'Pendientes de Reposición', icono: Icons.hourglass_bottom, moduleKey: 'pendientes_reposicion'),
        SubModulo(titulo: 'Negocio', icono: Icons.store_outlined, moduleKey: 'negocio', soloAdmin: true),
        SubModulo(titulo: 'Registro de Colores', icono: Icons.palette_outlined, moduleKey: 'colores'),
        SubModulo(titulo: 'Dispositivos', icono: Icons.devices_outlined, moduleKey: 'dispositivos', soloAdmin: true),
        SubModulo(titulo: 'Descuentos y Promociones', icono: Icons.local_offer_outlined, moduleKey: 'promociones', soloAdmin: true),
      ],
    ),
    ModuloMenu(
      titulo: 'Ventas',
      icono: Icons.point_of_sale_outlined,
      color: const Color(0xFF22C55E),
      subModulos: [
        SubModulo(titulo: 'Registrar Venta', icono: Icons.add_shopping_cart_outlined, moduleKey: 'ventas_registrar'),
        SubModulo(titulo: 'Ver Detalle', icono: Icons.receipt_long_outlined, moduleKey: 'ventas_detalle'),
      ],
    ),
    ModuloMenu(
      titulo: 'Compras',
      icono: Icons.shopping_cart_outlined,
      color: const Color(0xFFF59E0B),
      subModulos: [
        SubModulo(titulo: 'Registrar Compra', icono: Icons.add_box_outlined, moduleKey: 'compras_registrar'),
        SubModulo(titulo: 'Ver Detalle', icono: Icons.receipt_long_outlined, moduleKey: 'compras_detalle'),
        SubModulo(titulo: 'Hacer Pedido', icono: Icons.local_shipping_outlined, moduleKey: 'compras_pedido', soloAdmin: true),
      ],
    ),
    ModuloMenu(
      titulo: 'Clientes',
      icono: Icons.groups_outlined,
      color: const Color(0xFF3B82F6),
      subModulos: [
        SubModulo(titulo: 'Clientes', icono: Icons.groups_outlined, moduleKey: 'clientes'),
      ],
    ),
    ModuloMenu(
      titulo: 'Proveedores',
      icono: Icons.local_shipping_outlined,
      color: const Color(0xFF8B5CF6),
      subModulos: [
        SubModulo(titulo: 'Proveedores', icono: Icons.local_shipping_outlined, moduleKey: 'proveedores'),
      ],
    ),
    // El módulo aparte "Referidores" que existió acá se eliminó: el dueño
    // pidió explícitamente que un referidor sea solo un cliente marcado con
    // ClienteModel.esReferidor, manejado desde ClientesScreen (que ahora
    // tiene una vista "Referidores" propia), no una sección de menú
    // separada.
    ModuloMenu(
      titulo: 'Créditos',
      icono: Icons.credit_card_outlined,
      color: const Color(0xFFEC4899),
      subModulos: [
        SubModulo(titulo: 'Ventas Crédito', icono: Icons.credit_score_outlined, moduleKey: 'ventas_credito'),
        SubModulo(titulo: 'Compras Crédito', icono: Icons.credit_score_outlined, moduleKey: 'compras_credito'),
      ],
    ),
    ModuloMenu(
      titulo: 'Reportes',
      icono: Icons.bar_chart_outlined,
      color: const Color(0xFF64748B),
      subModulos: [
        SubModulo(titulo: 'Reporte de Ventas', icono: Icons.trending_up_outlined, moduleKey: 'reporte_ventas'),
        SubModulo(titulo: 'Reporte de Compras', icono: Icons.trending_down_outlined, moduleKey: 'reporte_compras'),
        SubModulo(titulo: 'Reporte Financiero', icono: Icons.account_balance_outlined, moduleKey: 'reporte_financiero', soloAdmin: true),
        SubModulo(titulo: 'Cierre de Caja', icono: Icons.point_of_sale_outlined, moduleKey: 'cierre_caja'),
        SubModulo(titulo: 'Ingresos-Egresos', icono: Icons.swap_vert_outlined, moduleKey: 'ingresos_egresos'),
      ],
    ),
  ];
}