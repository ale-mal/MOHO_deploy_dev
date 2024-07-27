locals {
    kubeconfig = templatefile("${path.module}/templates/kubeconfig.tpl", {
        cluster_name     = data.aws_eks_cluster.cluster.name
        cluster_endpoint = data.aws_eks_cluster.cluster.endpoint
        cluster_ca       = data.aws_eks_cluster.cluster.certificate_authority[0].data
        token            = nonsensitive(data.aws_eks_cluster_auth.cluster.token)
    })
}