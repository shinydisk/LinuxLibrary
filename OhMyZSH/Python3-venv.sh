#!/bin/bash

# Fonction pour créer un environnement virtuel
create_virtualenv() {
    echo "\n--- Création d'un environnement virtuel Python ---"

    # Demander le chemin du répertoire pour l'environnement
    read -p "Entrez le chemin complet du répertoire où créer l'environnement virtuel : " env_path

    # Vérifier si le répertoire existe
    if [ ! -d "$env_path" ]; then
        read -p "Le répertoire '$env_path' n'existe pas. Voulez-vous le créer ? (oui/non) : " create_dir
        case $create_dir in
            oui|o|yes|y)
                mkdir -p "$env_path"
                if [ $? -eq 0 ]; then
                    echo "Répertoire créé : $env_path"
                else
                    echo "Erreur lors de la création du répertoire."
                    exit 1
                fi
                ;;
            *)
                echo "Action annulée. Aucune modification n'a été effectuée."
                exit 0
                ;;
        esac
    fi

    # Vérifier si le chemin spécifié est bien un répertoire
    if [ ! -d "$env_path" ]; then
        echo "Erreur : Le chemin '$env_path' n'est pas un répertoire valide."
        exit 1
    fi

    # Créer l'environnement virtuel
    python3 -m venv "$env_path"
    if [ $? -eq 0 ]; then
        echo "Environnement virtuel créé avec succès dans : $env_path"
    else
        echo "Erreur lors de la création de l'environnement virtuel."
        exit 1
    fi
}

# Appeler la fonction
create_virtualenv
