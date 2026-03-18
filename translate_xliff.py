#!/usr/bin/env python3
"""
Complete translations for Portuguese, French, and Italian XLIFF files.
This script adds translations to all untranslated strings in the XLIFF files.
"""

import xml.etree.ElementTree as ET
import re
import os

# Translation dictionaries for common UI strings
translations = {
    "pt": {
        # Common actions
        "Add": "Adicionar",
        "Add project": "Adicionar projeto",
        "Add your first project": "Adicione seu primeiro projeto",
        "All time": "Todo o tempo",
        "Appearance": "Aparência",
        "Apply available update": "Aplicar atualização disponível",
        "Auto detect": "Detecção automática",
        "Automatic checks": "Verificações automáticas",
        "Back": "Voltar",
        "Back to workspace": "Voltar ao espaço de trabalho",
        "Branch": "Ramo",
        "Cancel": "Cancelar",
        "Changes": "Alterações",
        "Choose whether NeoCode follows the system language or always uses a specific app language.": "Escolha se o NeoCode segue o idioma do sistema ou sempre usa um idioma específico do aplicativo.",
        "Close": "Fechar",
        "Code font": "Fonte de código",
        "Code font size": "Tamanho da fonte de código",
        "Commit": "Commit",
        "Commit and create PR": "Commit e criar PR",
        "Commit and push": "Commit e push",
        "Commit message": "Mensagem de commit",
        "Commit your changes": "Commit suas alterações",
        "Compact": "Compactar",
        "Composer": "Compositor",
        "Contrast": "Contraste",
        "Copy": "Copiar",
        "Copy theme": "Copiar tema",
        "Could not import theme JSON.": "Não foi possível importar o JSON do tema.",
        "Could not serialize the theme as JSON.": "Não foi possível serializar o tema como JSON.",
        "Current version": "Versão atual",
        "Dashboard": "Painel",
        "Dark": "Escuro",
        "Dark theme": "Tema escuro",
        "Delete": "Excluir",
        "Delete thread": "Excluir conversa",
        "Developer": "Desenvolvedor",
        "Enter a commit message": "Digite uma mensagem de commit",
        "Expand project": "Expandir projeto",
        "Export": "Exportar",
        "Foreground": "Primeiro plano",
        "French": "Francês",
        "General": "Geral",
        "Git": "Git",
        "History": "Histórico",
        "Include unstaged": "Incluir não preparados",
        "Italian": "Italiano",
        "Language": "Idioma",
        "Last 30 days": "Últimos 30 dias",
        "Last 7 days": "Últimos 7 dias",
        "Last 90 days": "Últimos 90 dias",
        "Last activity": "Última atividade",
        "Last checked": "Última verificação",
        "Last workspace": "Último espaço de trabalho",
        "Light": "Claro",
        "Light theme": "Tema claro",
        "Model": "Modelo",
        "Name": "Nome",
        "Never": "Nunca",
        "Next steps": "Próximos passos",
        "No activity": "Sem atividade",
        "No apps found.": "Nenhum aplicativo encontrado.",
        "No changes are ready to commit.": "Nenhuma alteração pronta para commit.",
        "No languages found.": "Nenhum idioma encontrado.",
        "No monospaced fonts found.": "Nenhuma fonte monoespaçada encontrada.",
        "No projects yet": "Nenhum projeto ainda",
        "No ranges available.": "Nenhum intervalo disponível.",
        "No staged files are ready to commit.": "Nenhum arquivo preparado está pronto para commit.",
        "No threads found": "Nenhuma conversa encontrada",
        "No tool activity has been cached yet.": "Nenhuma atividade de ferramenta foi armazenada em cache ainda.",
        "No tracked projects are ready yet.": "Nenhum projeto rastreado está pronto ainda.",
        "Not available": "Não disponível",
        "Notify when a response finishes": "Notificar quando uma resposta terminar",
        "Notify when input is required": "Notificar quando a entrada é necessária",
        "On launch": "Na inicialização",
        "Open project with": "Abrir projeto com",
        "Portuguese": "Português",
        "Preparing the dashboard": "Preparando o painel",
        "Prevent Mac sleep while responses are running": "Prevenir suspensão do Mac enquanto as respostas estão em execução",
        "Projects": "Projetos",
        "Prompt": "Prompt",
        "Reasoning": "Raciocínio",
        "Rename": "Renomear",
        "Rename Thread": "Renomear conversa",
        "Restore drafts when reopening threads": "Restaurar rascunhos ao reabrir conversas",
        "Save": "Salvar",
        "Search apps": "Pesquisar aplicativos",
        "Search languages": "Pesquisar idiomas",
        "Search UI fonts": "Pesquisar fontes de interface",
        "Send messages with": "Enviar mensagens com",
        "Session autonomy": "Autonomia da sessão",
        "Settings": "Configurações",
        "Spanish": "Espanhol",
        "Sparkle delivery": "Entrega Sparkle",
        "Startup & workspace": "Inicialização e espaço de trabalho",
        "System": "Sistema",
        "Theme": "Tema",
        "Thread name": "Nome da conversa",
        "Threads": "Conversas",
        "Today": "Hoje",
        "Tool Activity": "Atividade de ferramenta",
        "Type": "Tipo",
        "UI font": "Fonte da interface",
        "UI font size": "Tamanho da fonte da interface",
        "Usage": "Uso",
        "Updates": "Atualizações",
        "Use custom": "Usar personalizado",
        "Use pointer cursors": "Usar cursores de ponteiro",
        "Welcome to NeoCode!": "Bem-vindo ao NeoCode!",
        "Will steer the agent at the next possible moment.": "Vai dirigir o agente no próximo momento possível.",
        "Waiting for the current response to finish before sending.": "Aguardando a resposta atual terminar antes de enviar.",
        "YOLO": "YOLO",
        "YOLO mode": "Modo YOLO",
        "accent color": "cor de destaque",
        "messages": "mensagens",
        "tokens": "tokens",
    },
    "fr": {
        # Common actions
        "Add": "Ajouter",
        "Add project": "Ajouter un projet",
        "Add your first project": "Ajoutez votre premier projet",
        "All time": "Tout le temps",
        "Appearance": "Apparence",
        "Apply available update": "Appliquer la mise à jour disponible",
        "Auto detect": "Détection automatique",
        "Automatic checks": "Vérifications automatiques",
        "Back": "Retour",
        "Back to workspace": "Retour à l'espace de travail",
        "Branch": "Branche",
        "Cancel": "Annuler",
        "Changes": "Modifications",
        "Choose whether NeoCode follows the system language or always uses a specific app language.": "Choisissez si NeoCode suit la langue du système ou utilise toujours une langue d'application spécifique.",
        "Close": "Fermer",
        "Code font": "Police de code",
        "Code font size": "Taille de police de code",
        "Commit": "Commit",
        "Commit and create PR": "Commit et créer une PR",
        "Commit and push": "Commit et push",
        "Commit message": "Message de commit",
        "Commit your changes": "Commit vos modifications",
        "Compact": "Compacter",
        "Composer": "Compositeur",
        "Contrast": "Contraste",
        "Copy": "Copier",
        "Copy theme": "Copier le thème",
        "Could not import theme JSON.": "Impossible d'importer le JSON du thème.",
        "Could not serialize the theme as JSON.": "Impossible de sérialiser le thème en JSON.",
        "Current version": "Version actuelle",
        "Dashboard": "Tableau de bord",
        "Dark": "Sombre",
        "Dark theme": "Thème sombre",
        "Delete": "Supprimer",
        "Delete thread": "Supprimer la conversation",
        "Developer": "Développeur",
        "Enter a commit message": "Entrez un message de commit",
        "Expand project": "Développer le projet",
        "Export": "Exporter",
        "Foreground": "Premier plan",
        "French": "Français",
        "General": "Général",
        "Git": "Git",
        "History": "Historique",
        "Include unstaged": "Inclure non préparés",
        "Italian": "Italien",
        "Language": "Langue",
        "Last 30 days": "30 derniers jours",
        "Last 7 days": "7 derniers jours",
        "Last 90 days": "90 derniers jours",
        "Last activity": "Dernière activité",
        "Last checked": "Dernière vérification",
        "Last workspace": "Dernier espace de travail",
        "Light": "Clair",
        "Light theme": "Thème clair",
        "Model": "Modèle",
        "Name": "Nom",
        "Never": "Jamais",
        "Next steps": "Prochaines étapes",
        "No activity": "Aucune activité",
        "No apps found.": "Aucune application trouvée.",
        "No changes are ready to commit.": "Aucune modification prête à être commitée.",
        "No languages found.": "Aucune langue trouvée.",
        "No monospaced fonts found.": "Aucune police monospace trouvée.",
        "No projects yet": "Aucun projet encore",
        "No ranges available.": "Aucune plage disponible.",
        "No staged files are ready to commit.": "Aucun fichier préparé n'est prêt à être commité.",
        "No threads found": "Aucune conversation trouvée",
        "No tool activity has been cached yet.": "Aucune activité d'outil n'a encore été mise en cache.",
        "No tracked projects are ready yet.": "Aucun projet suivi n'est encore prêt.",
        "Not available": "Non disponible",
        "Notify when a response finishes": "Notifier quand une réponse se termine",
        "Notify when input is required": "Notifier quand une entrée est requise",
        "On launch": "Au lancement",
        "Open project with": "Ouvrir le projet avec",
        "Portuguese": "Portugais",
        "Preparing the dashboard": "Préparation du tableau de bord",
        "Prevent Mac sleep while responses are running": "Empêcher la mise en veille du Mac pendant l'exécution des réponses",
        "Projects": "Projets",
        "Prompt": "Prompt",
        "Reasoning": "Raisonnement",
        "Rename": "Renommer",
        "Rename Thread": "Renommer la conversation",
        "Restore drafts when reopening threads": "Restaurer les brouillons lors de la réouverture des conversations",
        "Save": "Enregistrer",
        "Search apps": "Rechercher des applications",
        "Search languages": "Rechercher des langues",
        "Search UI fonts": "Rechercher des polices d'interface",
        "Send messages with": "Envoyer des messages avec",
        "Session autonomy": "Autonomie de session",
        "Settings": "Paramètres",
        "Spanish": "Espagnol",
        "Sparkle delivery": "Livraison Sparkle",
        "Startup & workspace": "Démarrage et espace de travail",
        "System": "Système",
        "Theme": "Thème",
        "Thread name": "Nom de la conversation",
        "Threads": "Conversations",
        "Today": "Aujourd'hui",
        "Tool Activity": "Activité des outils",
        "Type": "Type",
        "UI font": "Police d'interface",
        "UI font size": "Taille de police d'interface",
        "Usage": "Utilisation",
        "Updates": "Mises à jour",
        "Use custom": "Utiliser personnalisé",
        "Use pointer cursors": "Utiliser les curseurs pointeur",
        "Welcome to NeoCode!": "Bienvenue sur NeoCode!",
        "Will steer the agent at the next possible moment.": "Pilotera l'agent dès que possible.",
        "Waiting for the current response to finish before sending.": "En attente de la fin de la réponse actuelle avant d'envoyer.",
        "YOLO": "YOLO",
        "YOLO mode": "Mode YOLO",
        "accent color": "couleur d'accent",
        "messages": "messages",
        "tokens": "jetons",
    },
    "it": {
        # Common actions
        "Add": "Aggiungi",
        "Add project": "Aggiungi progetto",
        "Add your first project": "Aggiungi il tuo primo progetto",
        "All time": "Tutto il tempo",
        "Appearance": "Aspetto",
        "Apply available update": "Applica aggiornamento disponibile",
        "Auto detect": "Rilevamento automatico",
        "Automatic checks": "Controlli automatici",
        "Back": "Indietro",
        "Back to workspace": "Torna allo spazio di lavoro",
        "Branch": "Branch",
        "Cancel": "Annulla",
        "Changes": "Modifiche",
        "Choose whether NeoCode follows the system language or always uses a specific app language.": "Scegli se NeoCode segue la lingua di sistema o usa sempre una lingua specifica dell'app.",
        "Close": "Chiudi",
        "Code font": "Font codice",
        "Code font size": "Dimensione font codice",
        "Commit": "Commit",
        "Commit and create PR": "Commit e crea PR",
        "Commit and push": "Commit e push",
        "Commit message": "Messaggio di commit",
        "Commit your changes": "Commit delle tue modifiche",
        "Compact": "Compatta",
        "Composer": "Compositore",
        "Contrast": "Contrasto",
        "Copy": "Copia",
        "Copy theme": "Copia tema",
        "Could not import theme JSON.": "Impossibile importare il JSON del tema.",
        "Could not serialize the theme as JSON.": "Impossibile serializzare il tema come JSON.",
        "Current version": "Versione attuale",
        "Dashboard": "Dashboard",
        "Dark": "Scuro",
        "Dark theme": "Tema scuro",
        "Delete": "Elimina",
        "Delete thread": "Elimina conversazione",
        "Developer": "Sviluppatore",
        "Enter a commit message": "Inserisci un messaggio di commit",
        "Expand project": "Espandi progetto",
        "Export": "Esporta",
        "Foreground": "Primo piano",
        "French": "Francese",
        "General": "Generale",
        "Git": "Git",
        "History": "Cronologia",
        "Include unstaged": "Includi non staged",
        "Italian": "Italiano",
        "Language": "Lingua",
        "Last 30 days": "Ultimi 30 giorni",
        "Last 7 days": "Ultimi 7 giorni",
        "Last 90 days": "Ultimi 90 giorni",
        "Last activity": "Ultima attività",
        "Last checked": "Ultimo controllo",
        "Last workspace": "Ultimo spazio di lavoro",
        "Light": "Chiaro",
        "Light theme": "Tema chiaro",
        "Model": "Modello",
        "Name": "Nome",
        "Never": "Mai",
        "Next steps": "Prossimi passaggi",
        "No activity": "Nessuna attività",
        "No apps found.": "Nessuna app trovata.",
        "No changes are ready to commit.": "Nessuna modifica pronta per il commit.",
        "No languages found.": "Nessuna lingua trovata.",
        "No monospaced fonts found.": "Nessun font monospace trovato.",
        "No projects yet": "Nessun progetto ancora",
        "No ranges available.": "Nessun intervallo disponibile.",
        "No staged files are ready to commit.": "Nessun file staged è pronto per il commit.",
        "No threads found": "Nessuna conversazione trovata",
        "No tool activity has been cached yet.": "Nessuna attività strumento è stata ancora memorizzata nella cache.",
        "No tracked projects are ready yet.": "Nessun progetto tracciato è ancora pronto.",
        "Not available": "Non disponibile",
        "Notify when a response finishes": "Notifica quando una risposta finisce",
        "Notify when input is required": "Notifica quando è richiesto input",
        "On launch": "All'avvio",
        "Open project with": "Apri progetto con",
        "Portuguese": "Portoghese",
        "Preparing the dashboard": "Preparazione della dashboard",
        "Prevent Mac sleep while responses are running": "Impedisci la sospensione del Mac mentre le risposte sono in esecuzione",
        "Projects": "Progetti",
        "Prompt": "Prompt",
        "Reasoning": "Ragionamento",
        "Rename": "Rinomina",
        "Rename Thread": "Rinomina conversazione",
        "Restore drafts when reopening threads": "Ripristina bozze quando riapri le conversazioni",
        "Save": "Salva",
        "Search apps": "Cerca app",
        "Search languages": "Cerca lingue",
        "Search UI fonts": "Cerca font interfaccia",
        "Send messages with": "Invia messaggi con",
        "Session autonomy": "Autonomia sessione",
        "Settings": "Impostazioni",
        "Spanish": "Spagnolo",
        "Sparkle delivery": "Consegna Sparkle",
        "Startup & workspace": "Avvio e spazio di lavoro",
        "System": "Sistema",
        "Theme": "Tema",
        "Thread name": "Nome conversazione",
        "Threads": "Conversazioni",
        "Today": "Oggi",
        "Tool Activity": "Attività strumento",
        "Type": "Tipo",
        "UI font": "Font interfaccia",
        "UI font size": "Dimensione font interfaccia",
        "Usage": "Utilizzo",
        "Updates": "Aggiornamenti",
        "Use custom": "Usa personalizzato",
        "Use pointer cursors": "Usa cursori puntatore",
        "Welcome to NeoCode!": "Benvenuto in NeoCode!",
        "Will steer the agent at the next possible moment.": "Guiderà l'agente al prossimo momento possibile.",
        "Waiting for the current response to finish before sending.": "In attesa che la risposta attuale termini prima di inviare.",
        "YOLO": "YOLO",
        "YOLO mode": "Modalità YOLO",
        "accent color": "colore accento",
        "messages": "messaggi",
        "tokens": "token",
    },
}


def translate_xliff(input_file, output_file, lang_code):
    """Translate an XLIFF file using the translation dictionary."""

    # Read the file
    with open(input_file, "r", encoding="utf-8") as f:
        content = f.read()

    # Parse XML
    root = ET.fromstring(content)

    # XLIFF namespace
    ns = {"xliff": "urn:oasis:names:tc:xliff:document:1.2"}

    # Find all trans-unit elements
    file_elem = root.find(".//xliff:file", ns)
    if file_elem is None:
        print(f"Could not find file element in {input_file}")
        return

    body = file_elem.find(".//xliff:body", ns)
    if body is None:
        print(f"Could not find body element in {input_file}")
        return

    translated_count = 0

    for trans_unit in body.findall(".//xliff:trans-unit", ns):
        source_elem = trans_unit.find("xliff:source", ns)

        if source_elem is None:
            continue

        source_text = source_elem.text or ""

        # Check if we have a translation
        if source_text in translations[lang_code]:
            target_elem = trans_unit.find("xliff:target", ns)

            if target_elem is None:
                # Create target element
                target_elem = ET.SubElement(trans_unit, "target")
                target_elem.set("state", "translated")

            target_elem.text = translations[lang_code][source_text]
            target_elem.set("state", "translated")
            translated_count += 1

    # Write back with proper formatting
    # Use ElementTree to preserve structure
    tree = ET.ElementTree(root)

    # Register namespace
    ET.register_namespace("", "urn:oasis:names:tc:xliff:document:1.2")
    ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")

    tree.write(output_file, encoding="utf-8", xml_declaration=True)

    print(f"Translated {translated_count} strings for {lang_code}")


def main():
    base_dir = "/Users/watzon/Projects/personal/NeoCode/Localizations"

    languages = [
        ("pt", "pt.xcloc/Localized Contents/pt.xliff"),
        ("fr", "fr.xcloc/Localized Contents/fr.xliff"),
        ("it", "it.xcloc/Localized Contents/it.xliff"),
    ]

    for lang_code, relative_path in languages:
        input_file = os.path.join(base_dir, relative_path)

        if not os.path.exists(input_file):
            print(f"File not found: {input_file}")
            continue

        print(f"\nProcessing {lang_code}...")
        translate_xliff(input_file, input_file, lang_code)
        print(f"✓ Updated {input_file}")


if __name__ == "__main__":
    main()
