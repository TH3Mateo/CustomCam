#!/usr/bin/env python3
"""
Skrypt generujący plik projektu syntezy Gowin (.prj) z plików źródłowych
zawartych w głównym pliku projektu (.gprj).

Użycie:
    python3 generate_synthesis_project.py <input.gprj> <output.prj>
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
    
    # Parsuj part number aby wyodrębnić pakiet i prędkość
    # Format: GW2AR-LV18QN88C8/I7
    # QN88 to pakiet (QFN88), C8 to prędkość (8)
    package = "QFN88"  # domyślnie
    speed = "8"        # domyślnie
    
    if 'QN88' in device_pn:
        package = "QFN88"
    if 'C8' in device_pn:
        speed = "8"
    
    # Wyodrębnij pliki Verilog
    verilog_files = []
    file_list = root.find('FileList')
    if file_list is not None:
        for file_elem in file_list.findall('File'):
            file_type = file_elem.get('type')
            file_enable = file_elem.get('enable', '1')
            
            # Dodaj tylko pliki Verilog, które są włączone
            if file_type == 'file.verilog' and file_enable == '1':
                file_path = file_elem.get('path')
                verilog_files.append(file_path)
    
    return {
        'device_name': device_name,
        'device_pn': device_pn,
        'package': package,
        'speed': speed,
        'verilog_files': verilog_files
    }


def generate_prj(project_info, output_file, project_root):
    """Generuje plik .prj dla GowinSynthesis."""
    
    # Utwórz katalog wyjściowy jeśli nie istnieje
    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    
    # Ścieżka bezwzględna do katalogu projektu
    project_root_abs = os.path.abspath(project_root)
    
    # Utwórz strukturę XML
    root = ET.Element('Project')
    
    # Dodaj wersję
    version = ET.SubElement(root, 'Version')
    version.text = 'beta'
    
    # Dodaj informacje o urządzeniu
    device = ET.SubElement(root, 'Device')
    device.set('id', project_info['device_name'])
    device.set('package', project_info['package'])
    device.set('speed', project_info['speed'])
    device.set('partNumber', project_info['device_pn'])
    
    # Dodaj listę plików
    file_list = ET.SubElement(root, 'FileList')
    for verilog_file in project_info['verilog_files']:
        # Stwórz absolutną ścieżkę
        if not os.path.isabs(verilog_file):
            abs_path = os.path.join(project_root_abs, verilog_file)
        else:
            abs_path = verilog_file
        
        # Normalizuj ścieżkę
        abs_path = os.path.normpath(abs_path)
        
        file_elem = ET.SubElement(file_list, 'File')
        file_elem.set('path', abs_path)
        file_elem.set('type', 'verilog')
    
    # Dodaj opcje syntezy
    option_list = ET.SubElement(root, 'OptionList')
    
    options = [
        ('disable_insert_pad', '0'),
        ('looplimit', '2000'),
        ('output_file', os.path.join(project_root_abs, 'impl/gwsynthesis', 
                                     Path(output_file).stem + '.vg')),
        ('print_all_synthesis_warning', '1'),
        ('ram_rw_check', '0'),
        ('verilog_language', "sysv-2017"),
        ('vhdl_language', 'vhdl-1993'),
    ]
    
    for opt_type, opt_value in options:
        option = ET.SubElement(option_list, 'Option')
        option.set('type', opt_type)
        option.set('value', opt_value)
    
    # Zapisz do pliku z ładnym formatowaniem
    tree = ET.ElementTree(root)
    ET.indent(tree, space='    ')
    
    with open(output_file, 'wb') as f:
        f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(b'<!DOCTYPE gowin-synthesis-project>\n')
        tree.write(f, encoding='UTF-8', xml_declaration=False)
        f.write(b'\n')
    
    print(f"Wygenerowano plik syntezy: {output_file}")
    print(f"Pliki źródłowe ({len(project_info['verilog_files'])}):")
    for f in project_info['verilog_files']:
        print(f"  - {f}")


def main():
    if len(sys.argv) != 3:
        print("Użycie: generate_synthesis_project.py <input.gprj> <output.prj>")
        print()
        print("Przykład:")
        print("  python3 generate_synthesis_project.py dac_drive.gprj impl/gwsynthesis/dac_drive.prj")
        sys.exit(1)
    
    gprj_file = sys.argv[1]
    prj_file = sys.argv[2]
    
    # Katalog projektu to katalog gdzie jest plik .gprj
    project_root = os.path.dirname(os.path.abspath(gprj_file))
    if not project_root:
        project_root = '.'
    
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
    
    # Generuj plik .prj
    try:
        generate_prj(project_info, prj_file, project_root)
    except Exception as e:
        print(f"Błąd generowania {prj_file}: {e}")
        sys.exit(1)
    
    print("Gotowe!")


if __name__ == '__main__':
    main()
