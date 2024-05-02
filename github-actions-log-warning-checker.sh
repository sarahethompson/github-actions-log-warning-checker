#!/bin/bash
# DOT NOT REMOVE TRAILING NEW LINE IN THE INPUT CSV FILE

# Usage: 
# Step 0: Run `gh auth login` to authenticate with GitHub CLI
# Step 1: Run ./generate-repos.sh <org> > repos.csv
#    (or create a list of repos in a csv file, 1 per line, with a trailing empty line at the end of the file)
# Step 2: ./github-actions-log-warning-checker.sh repos.csv output.csv

WORKFLOW_RUNS_TO_CHECK=2
WARNING_LOG_MESSAGES=("Node.js 16 actions are deprecated")

if [ $# -lt "2" ]; then
    echo "Usage: $0 <repo_filename> <output_filename>"
    exit 1
fi

filename="$1"
output="$2"

if [ ! -f "$filename" ]; then
    echo "Repo input file $filename does not exist"
    exit 1
fi

# mv output file if it exists
if [ -f "$output" ]; then
    date=$(date +"%Y-%m-%d %T")
    mv $output "$output-$date.csv"
fi

echo "repo,workflow_name,workflow_url,finding,found_in_latest_workflow_run,actions" > $output

while read -r repofull ; 
do
    IFS='/' read -ra data <<< "$repofull"

    org=${data[0]}
    repo=${data[1]}

    echo $"> Checking repo for warnings in actions runs: $org/$repo"

    # get each workflow id
    workflows=$(gh api /repos/$org/$repo/actions/workflows)
    echo $workflows | jq -c -r '.workflows[]' | while read -r workflow ; do
        workflow_id=$(echo $workflow | jq -r '.id')
        workflow_path=$(echo $workflow | jq -r '.path')
        workflow_name=$(echo $workflow | jq -r '.name')
        workflow_url=$(echo $workflow | jq -r '.html_url')
        echo "  >> Checking workflow: $workflow_name ($workflow_path) $workflow_id"
        # will get the most recent x workflow file run(s)
        runs=$(gh api --method GET /repos/$org/$repo/actions/workflows/$workflow_id/runs -F per_page=$WORKFLOW_RUNS_TO_CHECK)
        i=0
        echo $runs | jq -c -r '.workflow_runs[]' | while read -r run ; do
            run_id=$(echo $run | jq -r '.id')
            run_display_title=$(echo $run | jq -r '.display_title')
            echo "    >> Checking run: $run_display_title ($run_id)"
            run_output=$(gh run view $run_id -R $org/$repo)
            for warning_message in "${WARNING_LOG_MESSAGES[@]}"; do
                if [[ $run_output == *"$warning_message"* ]]; then
                    # determine if this is a deprecated workflow command or deprecated node12 action
                    case $warning_message in
                    "${WARNING_LOG_MESSAGES[0]}"*)
                        FINDING="Node.js 16 action"
                        #ACTION=$(echo "$run_output" | grep -oP'(?<=! Node.js 16 actions are deprecated. Please update the following actions to use Node.js 20: ).*')
                        #grep -oP '(?<=! Node.js 16 actions are deprecated. Please update the following actions to use Node.js 20: ).*' file.txt
                        ACTION=$(echo "$run_output" | grep -o '.*Please update the following actions to use Node.js 20.*\. ' | cut -f2- -d:)
                        suffix=". For more information see: https://github.blog/changelog/2023-09-22-github-actions-transitioning-from-node-16-to-node-20/."
                        #sed 's/\.$//'
                        NL=$'\n'
                        ACTION=${ACTION//$NL/,}
                        ACTION=${ACTION%"$suffix"}
                        ACTION=${ACTION//,/ }
                        ACTION=${ACTION//. /}
                        ;;
                    esac
                    # find if this was found in the latest run or not
                    latest=$([ "$i" -eq 0 ] && echo "yes" || echo "no")
                    # print the results
                    echo "$org/$repo,$workflow_name,$workflow_url,$FINDING,$latest,$ACTION" >> "$output"
                    break 2
                fi
            done
            i=$((i+1))
        done
    done


done < "$filename"



# example of warning
# Warning: The `set-output` command is deprecated and will be disabled soon. Please upgrade to using Environment Files. For more information see: https://github.blog/changelog/2022-10-11-github-actions-deprecating-save-state-and-set-output-commands/
# Warning: Node.js 12 actions are deprecated. Please update the following actions to use Node.js 16: aws-actions/configure-aws-credentials@67fbcbb121271f7775d2e7715933280b06314838. For more information see: https://github.blog/changelog/2022-09-22-github-actions-all-actions-will-begin-running-on-node16-instead-of-node12/.
