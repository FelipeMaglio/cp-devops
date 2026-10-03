package br.com.dimdim.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.*;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "TRANSACAO")
public class Transacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "ID_TRANSACAO")
    private Long id;

    @JsonIgnore
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_CLIENTE", nullable = false)
    private Cliente cliente;

    @NotBlank
    @Size(max = 20)
    @Column(name = "TIPO", nullable = false, length = 20)
    private String tipo;

    @NotNull
    @DecimalMin("0.01")
    @Column(name = "VALOR", nullable = false, precision = 12, scale = 2)
    private BigDecimal valor;

    @Column(name = "DT_TRANSACAO")
    private LocalDateTime dtTransacao;

    @PrePersist
    void prePersist() {
        if (dtTransacao == null) dtTransacao = LocalDateTime.now();
    }

    @JsonProperty("idCliente")
    public Long getIdCliente() {
        return cliente != null ? cliente.getId() : null;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Cliente getCliente() { return cliente; }
    public void setCliente(Cliente cliente) { this.cliente = cliente; }
    public String getTipo() { return tipo; }
    public void setTipo(String tipo) { this.tipo = tipo; }
    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }
    public LocalDateTime getDtTransacao() { return dtTransacao; }
    public void setDtTransacao(LocalDateTime dtTransacao) { this.dtTransacao = dtTransacao; }
}
