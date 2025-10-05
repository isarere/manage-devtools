# !/bin/bash

instance=$1
bundletype=$2

if [ -z "$instance" ] || [ -z "$bundletype" ]; then
  echo "Usage: $0 <instance> <bundletype>"
  echo "ex: $0 dev1 all"
  exit 1
fi
# récupérer le spec du deployment original

original_deployment_spec=$(oc get deployment/$instance-mas-$bundletype -oyaml | yq '.spec.template.spec')
echo "Original deployment spec:::::::::::::::::::::::::::::::::::::::::::"
printf "$original_deployment_spec" 
if [ -z "$original_deployment_spec" ] || [ "$original_deployment_spec" = "null" ]; then
  echo "Erreur: Impossible de récupérer le spec du deployment original."
  exit 1
fi

# ajouter port 7777 sur .spec.template.spec.containers.resources.ports où .spec.template.spec.containers.resources.image contient $instance-mas-$bundletype
echo "Ajout du port 7777 à la configuration du conteneur dont l'image contient '$instance-mas-$bundletype'..."
modified_deployment_spec=$(yq '(.containers[] | select(.image | test("'"$instance-mas-$bundletype"'"))).ports += [{"containerPort": 7777, "protocol": "TCP"}]' <<< "$original_deployment_spec")

echo "modifier args de démarrage pour debug"
# Update cmd args for the Maximo® Manage server. Replace /tmp/startwlp.sh; with /tmp/genJDBCTruststore.sh; /opt/ibm/wlp/bin/server debug defaultServer;
modified_deployment_spec=$(sed 's|/tmp/startwlp.sh;|/tmp/genJDBCTruststore.sh; /opt/ibm/wlp/bin/server debug defaultServer;|g' <<< "$modified_deployment_spec")
echo "modified_deployment_spec:"
echo "$modified_deployment_spec" > modified_deployment_spec.yaml

# Générer le fichier debug_deployment_template.json avec les variables d'environnement

debug_deployment_name="$instance-mas-$bundletype-debug-$(whoami)"

# Update the initial_deployment.yaml with the correct instance and bundletype values
updated_deployment_yaml=$(yq '
	.metadata.name = "'"$debug_deployment_name"'" |
	.spec.template.spec = load("modified_deployment_spec.yaml") |
	.spec.selector.matchLabels.app = "'"$debug_deployment_name"'" |
	.spec.template.metadata.labels.app = "'"$debug_deployment_name"'"
' <<< "$(cat initial_deployment.yaml)")

echo "$updated_deployment_yaml" > new_debug_deployment.yaml

oc apply -f new_debug_deployment.yaml

debug_pod_name=$(oc get pods -l app=$debug_deployment_name -o jsonpath="{.items[0].metadata.name}")
echo "Debug pod name: $debug_pod_name"
kubectl port-forward $debug_pod_name 7777:7777