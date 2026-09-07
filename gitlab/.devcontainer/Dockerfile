# Start from the official Ansible image
FROM quay.io/ansible/creator-ee:latest

# Switch to root to install packages
USER root

# Install packages without updating repos first to avoid proxy issues
RUN microdnf install -y tmux vi vim tree tig sshpass --nodocs && \
    microdnf clean all

# Create /etc/ansible directory if it doesn't exist
RUN mkdir -p /etc/ansible

# Create vault password file
RUN echo 'fischersfritz33143' > /etc/ansible/vaultpass.txt && \
    chmod 640 /etc/ansible/vaultpass.txt

# Create ansible.cfg
RUN echo '[defaults]' > /etc/ansible/ansible.cfg && \
    echo 'host_key_checking = False' >> /etc/ansible/ansible.cfg && \
    echo 'vault_password_file = /etc/ansible/vaultpass.txt' >> /etc/ansible/ansible.cfg

# Create .bashrc with aliases in /root
RUN echo "alias ll='ls -la'" > /root/.bashrc && \
    echo "alias play='ansible-playbook'" >> /root/.bashrc && \
    echo "alias tm='tmux'" >> /root/.bashrc && \
    echo "alias tma='tmux attach'" >> /root/.bashrc && \
    echo "alias tml='tmux list-sessions'" >> /root/.bashrc && \
    echo "alias t='tree'" >> /root/.bashrc && \
    echo "alias gs='git status'" >> /root/.bashrc && \
    echo "alias ga='git add'" >> /root/.bashrc && \
    echo "alias gcm='git commit -m'" >> /root/.bashrc && \
    echo "alias vault='ansible-vault'" >> /root/.bashrc

# Set working directory
WORKDIR /workspace