#!/usr/bin/env python3
"""
Skrypt generujący plik TCL dla Place and Route (run_pnr.tcl) z plików
zawartych w głównym pliku projektu (.gprj).

Użycie:
    python3 generate_pnr_script.py <input.gprj> <output.tcl>
"""

import xml.etree.ElementTree as ET
import sys
import os
from pathlib import Path


def parse_gprj(gprj_file):
    """Parsuje plik .gprj i zwraca informacje o projekcie."""
    tree = ET.parse(gprj_file)
    root = tree.getroot()
    
    # Wyodrębnij informacje o urządzeniu
    device = root.find('Device')
    device_name = device.get('name')
    device_pn = device.get('pn')
    
    # Wyodrębnij pliki constraints
    cst_file = None
    sdc_file = None
    
    file_list = root.find('FileList')
    if file_list is not None:
        for file_elem in file_list.findall('File'):
            file_type = file_elem.get('type')
            file_enable = file_elem.get('enable', '1')
            file_path = file_elem.get('path')
            
            # Dodaj tylko pliki które są włączone
            if file_enable == '1':
                if file_type == 'file.cst':
                    cst_file = file_path
                elif file_type == 'file.sdc':
                    sdc_file = file_path
    
    return {
        'device_name': device_name,
        'device_pn': device_pn,
        'cst_file': cst_file,
        'sdc_file': sdc_file
    }


def generate_pnr_tcl(project_info, output_file, project_name, project_root):
    """Generuje plik TCL dla Place and Route."""
    
    # Utwórz katalog wyjściowy jeśli nie istnieje
    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    
    # Ścieżka bezwzględna do katalogu projektu
    project_root_abs = os.path.abspath(project_root)
    
    # Ścieżki do plików
    netlist_file = os.path.join(project_root_abs, 'impl/gwsynthesis', f'{project_name}.vg')
    
    # Przygotuj ścieżki do constraints (absolutne)
    cst_file_abs = None
    sdc_file_abs = None
    
    if project_info['cst_file']:
        if not os.path.isabs(project_info['cst_file']):
            cst_file_abs = os.path.join(project_root_abs, project_info['cst_file'])
        else:
            cst_file_abs = project_info['cst_file']
        cst_file_abs = os.path.normpath(cst_file_abs)
    
    if project_info['sdc_file']:
        if not os.path.isabs(project_info['sdc_file']):
            sdc_file_abs = os.path.join(project_root_abs, project_info['sdc_file'])
        else:
            sdc_file_abs = project_info['sdc_file']
        sdc_file_abs = os.path.normpath(sdc_file_abs)
    
    # Generuj zawartość pliku TCL
    tcl_content = []
    
    # Dodaj plik netlist
    tcl_content.append(f'add_file -type netlist "{netlist_file}"')
    
    # Dodaj pliki constraints
    if cst_file_abs:
        tcl_content.append(f'add_file -type cst "{cst_file_abs}"')
    
    if sdc_file_abs:
        tcl_content.append(f'add_file -type sdc "{sdc_file_abs}"')
    
    # Ustaw urządzenie
    tcl_content.append(f'set_device -name {project_info["device_name"]} {project_info["device_pn"]}')
    
    # Ustaw opcje
    tcl_content.append(f'set_option -output_base_name {project_name}')
    tcl_content.append('set_option -gen_text_timing_rpt 1')
    tcl_content.append('set_option -timing_driven 1')
    tcl_content.append('set_option -rpt_auto_place_io_info 1')
    # Piny dual-purpose oddane na GPIO. Bez tego PnR widzi limit 53 zwyklych I/O
    # i odrzuca projekt (PA2024), mimo wpisow w .cst - `device.cfg` nie wystarcza,
    # bo trafia dopiero do generowania bitstreamu.
    # JTAG zostaje wylaczony - musi byc czym programowac uklad.
    tcl_content.append('set_option -use_mspi_as_gpio 1')
    tcl_content.append('set_option -use_sspi_as_gpio 1')
    
    # Uruchom wszystko
    tcl_content.append('run all')
    tcl_content.append('')  # Pusta linia na końcu
    
    # Zapisz do pliku
    with open(output_file, 'w') as f:
        f.write('\n'.join(tcl_content))
    
    print(f"Wygenerowano skrypt PnR: {output_file}")
    print(f"Device: {project_info['device_name']} ({project_info['device_pn']})")
    print(f"Netlist: {netlist_file}")
    if cst_file_abs:
        print(f"CST: {cst_file_abs}")
    if sdc_file_abs:
        print(f"SDC: {sdc_file_abs}")


def main():
    if len(sys.argv) != 3:
        print("Użycie: generate_pnr_script.py <input.gprj> <output.tcl>")
        print()
        print("Przykład:")
        print("  python3 generate_pnr_script.py dac_drive.gprj impl/pnr/run_pnr.tcl")
        sys.exit(1)
    
    gprj_file = sys.argv[1]
    tcl_file = sys.argv[2]
    
    # Katalog projektu to katalog gdzie jest plik .gprj
    project_root = os.path.dirname(os.path.abspath(gprj_file))
    if not project_root:
        project_root = '.'
    
    # Nazwa projektu z pliku .gprj
    project_name = os.path.splitext(os.path.basename(gprj_file))[0]
    
    # Sprawdź czy plik .gprj istnieje
    if not os.path.exists(gprj_file):
        print(f"Błąd: Plik {gprj_file} nie istnieje!")
        sys.exit(1)
    
    # Parsuj plik projektu
    try:
        project_info = parse_gprj(gprj_file)
    except Exception as e:
        print(f"Błąd parsowania {gprj_file}: {e}")
        sys.exit(1)
    
    # Generuj plik TCL
    try:
        generate_pnr_tcl(project_info, tcl_file, project_name, project_root)
    except Exception as e:
        print(f"Błąd generowania {tcl_file}: {e}")
        sys.exit(1)
    
    print("Gotowe!")


if __name__ == '__main__':
    main()
