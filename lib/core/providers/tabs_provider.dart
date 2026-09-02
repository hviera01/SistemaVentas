import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tab_item.dart';

class TabsState {
  final List<TabItem> tabs;
  final int indiceActivo;

  TabsState({required this.tabs, required this.indiceActivo});
}

class TabsNotifier extends Notifier<TabsState> {
  @override
  TabsState build() {
    return TabsState(tabs: [], indiceActivo: 0);
  }

  void abrirTab(TabItem tab) {
    final existente = state.tabs.indexWhere((t) => t.id == tab.id);
    if (existente != -1) {
      state = TabsState(tabs: state.tabs, indiceActivo: existente);
      return;
    }
    final nuevaLista = [...state.tabs, tab];
    state = TabsState(tabs: nuevaLista, indiceActivo: nuevaLista.length - 1);
  }

  void cerrarTab(String id) {
    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final nuevaLista = [...state.tabs]..removeAt(index);
    int nuevoIndice = state.indiceActivo;
    if (nuevoIndice >= nuevaLista.length) {
      nuevoIndice = nuevaLista.length - 1;
    }
    state = TabsState(
      tabs: nuevaLista,
      indiceActivo: nuevoIndice < 0 ? 0 : nuevoIndice,
    );
  }

  void seleccionarTab(int index) {
    state = TabsState(tabs: state.tabs, indiceActivo: index);
  }

  void seleccionarTabPorId(String id) {
    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    state = TabsState(tabs: state.tabs, indiceActivo: index);
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);
